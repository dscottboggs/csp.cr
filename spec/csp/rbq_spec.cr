require "../spec_helper"

module CSP
  def self.yield
    nil
  end
end

require "../../src/rbq"

module Fixture
  CAP_EXP    = 3
  CAP        = 1 << Fixture::CAP_EXP
  ARRAY      = StaticArray(Int32, CAP).new { |i| CAP - i }
  ARRAY_COPY = StaticArray(Int32, CAP).new 0
end

{% for rbqt in %w(SS SM MS MM) %}

describe CSP::RBQ::{{rbqt.id}} do
  describe "#push? and #pop?" do
    it "works" do
      # shouldn't this be only able to hold one value for S-type queues?
      rbq = CSP::RBQ::{{rbqt.id}}(Int32).new Fixture::CAP_EXP
      Fixture::CAP.times { |i| (rbq.push? i).should be_true }
      (rbq.push? -1).should be_false
      (rbq.push? Fixture::ARRAY.to_slice).should eq 0

      Fixture::CAP.times do |i|
        if val = rbq.pop?
          val.should eq i
        else
          fail "failed to pop item ##{i}"
        end
      end

      rbq.pop?.should be_nil
      (rbq.pop? Fixture::ARRAY_COPY.to_slice).should eq 0
    end
  end
  describe "#push and #pop" do
    it "works" do
      rbq = CSP::RBQ::{{rbqt.id}}(Int32).new Fixture::CAP_EXP
      Fixture::CAP.times { |i| rbq.push i }

      rbq.push?(-1).should be_false
      rbq.push?(Fixture::ARRAY.to_slice).should eq 0

      Fixture::CAP.times do |i|
        rbq.pop.should eq i
      end
      rbq.pop?.should be_nil
      rbq.pop?(Fixture::ARRAY_COPY.to_slice).should eq 0
    end
  end
  describe "#push?(Slice(T)) and #pop?(Slice(T))" do
    it "works" do
      Fixture::ARRAY_COPY[] = 0
      rbq = CSP::RBQ::{{rbqt.id}}(Int32).new Fixture::CAP_EXP
      rbq.push?(Fixture::ARRAY.to_slice).should eq Fixture::ARRAY.size
      rbq.push?(-1).should be_false
      rbq.push?(Fixture::ARRAY.to_slice).should eq 0
      rbq.pop?(Fixture::ARRAY_COPY.to_slice).should eq Fixture::ARRAY.size
      Fixture::ARRAY_COPY.should eq Fixture::ARRAY
    end
  end
  describe "#push(Slice(T)) and #pop(Slice(T))" do
    it "works" do
      Fixture::ARRAY_COPY[] = 0
      rbq = CSP::RBQ::{{rbqt.id}}(Int32).new Fixture::CAP_EXP
      rbq.push Fixture::ARRAY.to_slice
      rbq.push?(-1).should be_false
      rbq.push?(Fixture::ARRAY.to_slice).should eq 0
      rbq.pop Fixture::ARRAY_COPY.to_slice
      Fixture::ARRAY_COPY.should eq Fixture::ARRAY
      rbq.pop?.should be_nil
      rbq.pop?(Fixture::ARRAY_COPY.to_slice).should eq 0
    end
  end
end
{% end %}