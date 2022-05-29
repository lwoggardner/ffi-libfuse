require_relative '../../spec_helper'
require_relative '../../../lib/ffi/libfuse/fuse_args'

describe FFI::Libfuse::FuseArgs do

  let(:argv) { %w[fs] }

  let(:args) { FFI::Libfuse::FuseArgs.create(*argv) }

  describe '#parse!' do

    [
      { name: 'boolean', input: '-ofoo', option: 'foo', exp_value: true},
      { name: 'parameter o_equals', input: '-ofoo=bar', option: 'foo=', exp_value: 'bar'},
      { name: 'parameter space short', input: '-f bar', option: '-f ', exp_value: 'bar'},
      { name: 'parameter space short single', input: '-fbar', option: '-f ', exp_value: 'bar'},
      { name: 'parameter space long', input: '-foo bar', option: '-foo ', exp_value: 'bar'},
      { name: 'parameter space long single', input: '-foobar', option: '-foo ', exp_value: 'bar'},
      { name: 'parameter o_space short', input: '-of bar', option: 'f ', exp_value: 'bar'},
      { name: 'parameter o_space short single', input: '-ofbar', option: 'f ', exp_value: 'bar'},
      { name: 'parameter o_space long', input: '-ofoo bar', option: 'foo ', exp_value: 'bar'},
      { name: 'parameter o_space long single', input: '-ofoobar', option: 'foo ', exp_value: 'bar'},
      { name: 'parameter dash equals', input: '-ofoo-bar=baz', option: 'foo-bar=', exp_value: 'baz'},
      { name: 'parameter underscore equals', input: '-ofoo_bar=baz', option: 'foo_bar=', exp_value: 'baz'},
    ].kw_each do |name:, input:, option:, exp_value:|

      # we're testing how we rubify fuse_parse_opt(), and confirming our assumptions about its behaviour
      it "extracts #{name} option" do
        argv << input
        called = []
        args.parse!({  option => :foo }) { |**p_args| called << p_args; :handled }
        _(called.size).must_equal(1)
        key, value, match = called.first.values_at(:key, :value, :match)

        _(key).must_equal(:foo)
        _(value).must_equal(exp_value)
        _(match).must_equal(option)

      end
    end
  end
end


