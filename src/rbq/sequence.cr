module CSP
  abstract class RBQ(T)
    struct Sequence
      property value : Atomic(UInt64)
      @_ : PaddingT
      delegate :get, :set, :compare_and_set, to: @value

      def initialize(@value)
        @_ = uninitialized PaddingT
      end

      def self.new(value : Number)
        new value.to_u64
      end
    end
  end
end
