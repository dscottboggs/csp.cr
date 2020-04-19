module CSP
  abstract struct RBQ
    alias PaddingT = UInt8[56]

    struct Sequence
      # Why is there padding? Should this be @[Packed]?
      @_ : PaddingT
      property value : Atomic(UInt64)
      delegate :get, :set, :compare_and_exchange, to: @value

      def initialize(@value)
        @_ = uninitialized PaddingT
      end
    end
  end
end
