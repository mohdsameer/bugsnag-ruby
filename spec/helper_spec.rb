# encoding: utf-8

require 'spec_helper'
require 'set'

describe Bugsnag::Helpers do

  describe "trim_if_needed" do

    it "breaks recursion" do
      a = [1, 2, 3]
      b = [2, a]
      a << b
      value = Bugsnag::Helpers.trim_if_needed(a)
      expect(value).to eq([1, 2, 3, [2, "[RECURSION]"]])
    end

    it "does not break equal objects without recursion" do
      data = [1, [1, 2], [1, 2], "a"]
      value = Bugsnag::Helpers.trim_if_needed(data)
      expect(value).to eq data
    end

    it "preserves bool types" do
      value = Bugsnag::Helpers.trim_if_needed([1, 3, true, "NO", "2", false])
      expect(value[2]).to be_a(TrueClass)
      expect(value[5]).to be_a(FalseClass)
    end

    it "preserves Numeric types" do
      value = Bugsnag::Helpers.trim_if_needed([1, 3.445, true, "NO", "2", false])
      expect(value[0]).to be_a(Numeric)
      expect(value[1]).to be_a(Numeric)
    end

    it "preserves String types" do
      value = Bugsnag::Helpers.trim_if_needed([1, 3, true, "NO", "2", false])
      expect(value[3]).to be_a(String)
      expect(value[4]).to be_a(String)
    end

    context "an object will throw if `to_s` is called" do
      class StringRaiser
        def to_s
          raise 'Oh no you do not!'
        end
      end

      it "uses the string '[RAISED]' instead" do
        value = Bugsnag::Helpers.trim_if_needed([1, 3, StringRaiser.new])
        expect(value[2]).to eq "[RAISED]"
      end
    end

    context "payload length is less than allowed" do

      it "does not change strings" do
        value = SecureRandom.hex(4096)
        expect(Bugsnag::Helpers.trim_if_needed(value)).to eq value
      end

      it "does not change arrays" do
        value = 1000.times.map {|i| "#{i} - #{i + 1}" }
        expect(Bugsnag::Helpers.trim_if_needed(value)).to eq value
      end

      it "does not change hashes" do
        value = Hash[*1000.times.map{|i| ["#{i}", i]}.flatten]
        expect(Bugsnag::Helpers.trim_if_needed(value)).to eq value
      end
    end

    context "payload length is greater than allowed" do

      context "value is a String" do
        it "trims length" do
          input = SecureRandom.hex(1_000_000)
          value = Bugsnag::Helpers.trim_if_needed(input)
          expect(value.length).to be <= Bugsnag::Helpers::MAX_STRING_LENGTH
        end
      end

      context "value is an Array" do
        it "trims nested string contents" do
          value = [[60.times.map {|i| SecureRandom.hex(8192) }]]
          json = ::JSON.dump(Bugsnag::Helpers.trim_if_needed(value))
          expect(json.length).to be < Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
        end

        it "trims string contents" do
          value = 60.times.map {|i| SecureRandom.hex(8192) }
          json = ::JSON.dump(Bugsnag::Helpers.trim_if_needed(value))
          expect(json.length).to be < Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
        end
      end

      context "value is a Set" do
        it "trims string contents" do
          value = Set.new(30.times.map {|i| SecureRandom.hex(8192) })
          json = ::JSON.dump(Bugsnag::Helpers.trim_if_needed(value))
          expect(json.length).to be < Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
        end
      end

      context "value can be converted to a String" do
        it "converts to a string and trims" do
          value = Set.new(30_000.times.map {|i| Bugsnag::Helpers })
          json = ::JSON.dump(Bugsnag::Helpers.trim_if_needed(value))
          expect(json.length).to be < Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
        end
      end

      context "value is a Hash" do

        before(:each) do
          @metadata = {
            :short_string => "this should not be truncated",
            :long_string => 10000.times.map {|i| "should truncate" }.join(""),
            :long_string_ary => 30.times.map {|i| SecureRandom.hex(8192) }
          }

          @trimmed_metadata = Bugsnag::Helpers.trim_if_needed @metadata
        end

        it "does not trim short values" do
          expect(@trimmed_metadata[:short_string]).to eq @metadata[:short_string]
        end

        it "trims long string values" do
          expect(@trimmed_metadata[:long_string].length).to eq(Bugsnag::Helpers::MAX_STRING_LENGTH)
          expect(@trimmed_metadata[:long_string].match(/\[TRUNCATED\]$/)).to_not be_nil
        end

        it "trims nested long string values" do
          @trimmed_metadata[:long_string_ary].each do |str|
            expect(str.match(/\[TRUNCATED\]$/)).to_not be_nil
            expect(str.length).to eq(Bugsnag::Helpers::MAX_STRING_LENGTH)
          end
        end

        it "does not change the argument value" do
          expect(@metadata[:long_string].length).to be > Bugsnag::Helpers::MAX_STRING_LENGTH
          expect(@metadata[:long_string].match(/\[TRUNCATED\]$/)).to be_nil
          expect(@metadata[:short_string].length).to eq(28)
          expect(@metadata[:short_string]).to eq("this should not be truncated")
          expect(@trimmed_metadata[:long_string_ary].length).to eq(30)
        end
      end

      context "and trimmed strings are not enough" do
        it "truncates long arrays" do
          value = [200.times.map {|i| SecureRandom.hex(8192) }, "a"]
          trimmed_value = Bugsnag::Helpers.trim_if_needed(value)
          expect(trimmed_value.length).to eq 2
          expect(trimmed_value.first.length).to eq Bugsnag::Helpers::MAX_ARRAY_LENGTH
          trimmed_value.first.each do |str|
            expect(str.match(/\[TRUNCATED\]$/)).to_not be_nil
            expect(str.length).to eq(Bugsnag::Helpers::MAX_STRING_LENGTH)
          end

          expect(::JSON.dump(trimmed_value).length).to be < Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
        end

        it "removes metadata from events" do
          metadata = Hash[*40000.times.map {|i| [i,i+1]}.flatten]
          frames = 50.times.map {|i| SecureRandom.hex(4096) }
          value = {key:"abc", events:[{metaData: metadata, frames: frames, cake: "carrot"}]}
          trimmed_value = Bugsnag::Helpers.trim_if_needed(value)
          expect(::JSON.dump(trimmed_value).length).to be < Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
          expect(trimmed_value[:key]).to eq value[:key]
          expect(trimmed_value[:events].first.keys.to_set).to eq [:frames, :cake].to_set
          expect(trimmed_value[:events].first[:metaData]).to be_nil
        end
      end

      context "and new trimming priorities are in place" do
        it "trims metadata strings first" do
          payload = {
            :events => [{
              :metaData => 50000.times.map {|i| "should truncate" }.join(""),
              :preserved => "Foo"
            }]
          }
          expect(::JSON.dump(payload).length).to be > Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
          trimmed = Bugsnag::Helpers.trim_if_needed(payload)
          expect(::JSON.dump(trimmed).length).to be <= Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
          expect(trimmed[:events][0][:metaData].length).to be <= Bugsnag::Helpers::MAX_STRING_LENGTH
          expect(trimmed[:events][0][:preserved]).to eq("Foo")
        end

        it "truncates metadata arrays" do
          payload = {
            :events => [{
              :metaData => 50000.times.map {|i| "should truncate" },
              :preserved => "Foo"
            }]
          }
          expect(::JSON.dump(payload).length).to be > Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
          trimmed = Bugsnag::Helpers.trim_if_needed(payload)
          expect(::JSON.dump(trimmed).length).to be <= Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
          expect(trimmed[:events][0][:metaData].length).to be <= Bugsnag::Helpers::MAX_ARRAY_LENGTH
          expect(trimmed[:events][0][:preserved]).to eq("Foo")
        end

        it "removes metadata altogether" do
          payload = {
            :events => [{
              :metaData => 20.times.map {|i| 20.times.map { |i| SecureRandom.hex(3000) } },
              :preserved => "Foo"
            }]
          }
          expect(::JSON.dump(payload).length).to be > Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
          trimmed = Bugsnag::Helpers.trim_if_needed(payload)
          expect(::JSON.dump(trimmed).length).to be <= Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
          expect(trimmed[:events][0][:metaData]).to be_nil
          expect(trimmed[:events][0][:preserved]).to eq("Foo")
        end

        it "trims stacktrace code, oldest first" do
          payload = {
            :events => [{
              :exceptions => [{
                :stacktrace => [
                  {
                    :lineNumber => 1,
                    :file => '/trace1',
                    :code => 50000.times.map {|i| "123456" }
                  },
                  {
                    :lineNumber => 2,
                    :file => '/trace2',
                    :code => 50000.times.map {|i| "123456" }
                  }
                ]
              }]
            }]
          }
          expect(::JSON.dump(payload).length).to be > Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
          trimmed = Bugsnag::Helpers.trim_if_needed(payload)
          expect(::JSON.dump(trimmed).length).to be <= Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
          trace = trimmed[:events][0][:exceptions][0][:stacktrace]
          expect(trace.length).to eq(2)
          expect(trace[0][:lineNumber]).to eq(1)
          expect(trace[0][:file]).to eq('/trace1')
          expect(trace[0][:code].length).to be > Bugsnag::Helpers::MAX_ARRAY_LENGTH
          expect(trace[1][:lineNumber]).to eq(2)
          expect(trace[1][:file]).to eq('/trace2')
          expect(trace[1][:code]).to be_nil
        end

        it "trims stacktrace entries, oldest first" do
          payload = {
            :events => [{
              :exceptions => [{
                :stacktrace => [
                  {
                    :lineNumber => 1,
                    :file => '/trace1',
                    :something => 50000.times.map {|i| "123456" }
                  },
                  {
                    :lineNumber => 2,
                    :file => '/trace2',
                    :something => 50000.times.map {|i| "123456" }
                  }
                ]
              }]
            }]
          }
          expect(::JSON.dump(payload).length).to be > Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
          trimmed = Bugsnag::Helpers.trim_if_needed(payload)
          expect(::JSON.dump(trimmed).length).to be <= Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
          trace = trimmed[:events][0][:exceptions][0][:stacktrace]
          expect(trace.length).to eq(1)
          expect(trace[0][:lineNumber]).to eq(1)
          expect(trace[0][:file]).to eq('/trace1')
          expect(trace[0][:something].length).to be > Bugsnag::Helpers::MAX_ARRAY_LENGTH
        end
      end
    end
  end
end
