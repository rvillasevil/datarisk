require 'test_helper'
require 'ostruct'

class AssistantRunnerTest < ActiveSupport::TestCase
  setup do
    @risk_assistant = risk_assistants(:one)
    @risk_assistant.messages.delete_all
  end

  def build_runner
    r = AssistantRunner.allocate
    r.instance_variable_set(:@risk_assistant, @risk_assistant)
    r
  end

  class DummyMessages
    def initialize(list)
      @list = list
    end

    def where(conds)
      return self unless conds[:key]
      DummyMessages.new(@list.select { |m| m[:key] == conds[:key] })
    end

    def order(*)
      self
    end

    def last
      val = @list.last
      val && OpenStruct.new(val)
    end
  end

  def build_runner_from_messages(messages)
    ra = OpenStruct.new(messages: DummyMessages.new(messages))
    runner = AssistantRunner.allocate
    runner.instance_variable_set(:@risk_assistant, ra)
    runner
  end

  test 'includes assistant instructions from config in run prompt' do
    instructions = "Pregunta con instrucciones del JSON"
    runner       = build_runner
    runner.instance_variable_set(:@thread_id, "thread_123")
    runner.instance_variable_set(:@fields_json, "{}")

    RiskFieldSet.stub :flat_fields, [] do
      RiskFieldSet.stub :by_id, { field: { id: "field", label: "Campo", assistant_instructions: instructions } } do
        RiskFieldSet.stub :question_for, ->(*) { "Pregunta base" } do
          RiskFieldSet.stub :normative_tips_for, ->(*) { "" } do
            captured_body = nil
            expected_schema = {
              type: "json_schema",
              json_schema: {
                name: "control_json_schema",
                schema: AssistantRunner::CONTROL_JSON_SCHEMA,
                strict: true
              }
            }            

            runner.stub :next_pending_field, :field do
              runner.stub :post, ->(url, body) { captured_body = body; { "id" => "run_123" } } do
                runner.send(:start_run_with_instructions)
              end
            end

            assert_includes captured_body[:additional_instructions], instructions
            assert_equal expected_schema, captured_body[:response_format]            
          end
        end
      end
    end
  end  

  test 'returns fields following JSON order including arrays' do
    fields = [
      { id: 'first', type: :string, parent: nil },
      { id: 'arr', type: :array_of_objects, parent: nil },
      { id: 'arr.name', type: :string, parent: 'arr' },
      { id: 'arr.subarr', type: :array_of_objects, parent: 'arr' },
      { id: 'arr.subarr.attr', type: :string, parent: 'arr.subarr' },
      { id: 'second', type: :string, parent: nil }
    ]

    by_id = fields.index_by { |f| f[:id].to_sym }

    RiskFieldSet.stub :flat_fields, fields do
      RiskFieldSet.stub :by_id, by_id do
        RiskFieldSet.stub :children_of_array, ->(id) { fields.select { |f| f[:parent] == id } } do
          runner = build_runner

          assert_equal :first, runner.next_pending_field

          @risk_assistant.messages.create!(sender: 'assistant', role: 'assistant', key: 'first', value: 'v', content: 'c')
          assert_equal :'arr.0.name', runner.next_pending_field

          @risk_assistant.messages.create!(sender: 'assistant', role: 'assistant', key: 'arr.0.name', value: 'v', content: 'c')
          assert_equal :'arr.0.subarr.0.attr', runner.next_pending_field

          @risk_assistant.messages.create!(sender: 'assistant', role: 'assistant', key: 'arr.0.subarr.0.attr', value: 'v', content: 'c')
          assert_equal :second, runner.next_pending_field
        end
      end
    end
  end

  test 'returns next missing field in arrays without count field' do
    child1 = { id: 'items.name', type: :string }
    child2 = { id: 'items.qty', type: :string }
    array  = { id: 'items', allow_add_remove_rows: true }

    RiskFieldSet.stub :by_id, {
      items: array,
      :'items.name' => child1,
      :'items.qty' => child2
    } do
      RiskFieldSet.stub :children_of_array, [child1, child2] do
        messages = [
          { key: 'items.0.name', value: 'a' },
          { key: 'items.0.qty',  value: '1' },
          { key: 'items.1.name', value: 'b' }
        ]
        runner = build_runner_from_messages(messages)
        answered = messages.map { |m| m[:key] }.to_set
        result = runner.send(:next_from_array, 'items', [], answered)
        assert_equal :'items.1.qty', result
      end
    end
  end

  test 'asks for new row when allow_add_remove_rows is true' do
    child1 = { id: 'things.desc', type: :string }
    array  = { id: 'things', allow_add_remove_rows: true }

    RiskFieldSet.stub :by_id, { things: array, :'things.desc' => child1 } do
      RiskFieldSet.stub :children_of_array, [child1] do
        messages = [ { key: 'things.0.desc', value: 'one' } ]
        runner = build_runner_from_messages(messages)
        answered = messages.map { |m| m[:key] }.to_set
        result = runner.send(:next_from_array, 'things', [], answered)
        assert_equal :'things.1.desc', result
      end
    end
  end

  test 'no extra rows requested when allow_add_remove_rows is false' do
    child1 = { id: 'recs.text', type: :string }
    array  = { id: 'recs', allow_add_remove_rows: false }

    RiskFieldSet.stub :by_id, { recs: array, :'recs.text' => child1 } do
      RiskFieldSet.stub :children_of_array, [child1] do
        messages = [ { key: 'recs.0.text', value: 'ok' } ]
        runner = build_runner_from_messages(messages)
        answered = messages.map { |m| m[:key] }.to_set
        result = runner.send(:next_from_array, 'recs', [], answered)
        assert_nil result
      end
    end
  end

end