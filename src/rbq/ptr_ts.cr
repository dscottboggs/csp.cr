require "./sequence"

module CSP
  abstract struct RBQ
    abstract struct PTR_T
      abstract def next
      abstract def barr
      abstract def update_barr(mask)
      abstract def mark_available(seq_v, mask)
      abstract def markm_available(start, _end, mask)
      abstract def next_rsv(current, n) : Bool
    end

    # what is SPTR?
    struct SPTR < PTR_T
      property next : UInt64
      atomic_property barr : RBQ::Sequence
      # Why is there padding? Should this be @[Packed]?
      @_ : PaddingT

      def initialize(cap)
        @next = 0
        @barr = RBQ::Sequence.new 0
        @_ = uninitialized PaddingT # it doesn't matter what's in padding
      end

      # why?
      def update_barr(mask)
        @barr.get
      end

      def mark_available(seq_v, mask)
        self.next
      end

      # what is 'm' here?
      def markm_available(start, _end, mask)
        self.next
      end

      # why?
      # what is rsv?
      def next_rsv(current, n)
        barr.set current + n
        true
      end
    end

    # what is MPTR? multiple pointer?
    struct MPTR < PTR_T
      atomic_property next : RBQ::Sequence = RBQ::Sequence.new 0
      atomic_property barr : RBQ::Sequence = RBQ::Sequence.new 0
      # Why is there padding? Should this be @[Packed]?
      @_ : PaddingT
      property stats : Slice(RBQ::Sequence)

      def initialize(capacity)
        @stats = Slice(RBQ::Sequence).new size: cap, value: -1
        @_ = uninitialized PaddingT # it doesn't matter what's in padding
      end

      def available?(seq_v, mask)
        stats[seq_v & mask].get == seq_v
      end

      def mark_available(seq_v, mask)
        stats[seq_v & mask].set seq_v
      end

      def markm_available(start, _end, mask) : Nil
        (start.._end).each { |i| mark_available i, mask }
      end

      def next_rsv(curr, n)
        @next.compare_and_exchange curr, curr + n
      end

      def update_barr(mask)
        current : UInt64 = self.barr
        _barr = current
        while available? _barr, mask
          _barr += 1
        end
        if current != _barr
          _, ok = @barr.compare_and_exchange current, _barr
          if ok
            _barr
          else
            self.barr
          end
        end
      end
    end
  end
end
