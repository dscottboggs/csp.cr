require "./sequence"
require "../common"

module CSP
  abstract class RBQ(T)
    abstract struct PtrT
      abstract def next
      abstract def barr
      abstract def update_barr(mask)
      abstract def mark_available(seq_v, mask)
      abstract def mark_available(start, _end, mask)
      abstract def next_rsv(current : UInt64, n : UInt64) : Bool
    end

    struct SPTR < PtrT
      atomic_property barr : RBQ::Sequence
      @_ : PaddingT

      def initialize(cap)
        @next = 0_u64
        @barr = RBQ::Sequence.new 0
        @_ = uninitialized PaddingT # it doesn't matter what's in padding
      end

      getter :next

      # Just returns the value of barr. Only here for API compatibility.
      def update_barr(mask)
        barr
      end

      def mark_available(seq_v, mask)
        self.next
      end

      def mark_available(start, _end, mask)
        self.next
      end

      # why?
      # what is rsv?
      def next_rsv(current : UInt64, n : UInt64)
        @barr.set current + n
        true
      end
    end

    struct MPTR < PtrT

      # A wrapper around the @stats property of an MPTR which
      # provides an indexable implementation.
      private struct StatsT
        include Indexable(Sequence)

        @stats : Slice(Sequence)

        def initialize(capacity)
          @stats = Slice(RBQ::Sequence).new size: capacity.to_i do
            RBQ::Sequence.new(UInt64::MAX).as RBQ::Sequence
          end
        end

        @[AlwaysInline]
        def size
          @stats.size
        end

        @[AlwaysInline]
        def unsafe_fetch(index)
          @stats.unsafe_fetch index
        end

        @[AlwaysInline]
        def []=(index, value)
          @stats[index].set value
        end
      end

      atomic_property next : RBQ::Sequence = RBQ::Sequence.new 0
      atomic_property barr : RBQ::Sequence = RBQ::Sequence.new 0
      # Why is there padding? Should this be @[Packed]?
      @_ : PaddingT
      property stats : StatsT

      def initialize(capacity)
        @stats = StatsT.new capacity
        @_ = uninitialized PaddingT # it doesn't matter what's in padding
      end

      private def available?(seq_v, mask)
        stats[seq_v & mask] == seq_v
      end

      def mark_available(seq_v, mask)
        stats[seq_v & mask] = seq_v
      end

      def mark_available(start, _end, mask) : Nil
        (start.._end).each { |i| mark_available i, mask }
      end

      def next_rsv(curr, n)
        @next.compare_and_set curr, curr + n
      end

      def update_barr(mask)
        current : UInt64 = self.barr
        _barr = current
        while available? _barr, mask
          _barr += 1
        end
        if current != _barr
          _, ok = @barr.compare_and_set current, _barr
          if ok
            _barr
          else
            current
          end
        else
          current
        end
      end
    end
  end
end
