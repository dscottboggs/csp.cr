module CSP
  abstract struct RBQ
    struct Items(T, I)
      @rbq : Pointer(RBQ)
      @items : Slice(T)

      def self.new(rbq : Pointer(RBQ), capacity : LibC::SizeT)
        new rbq, Slice(T).new(capacity)
      end

      def initialize(@rbq : Pointer(RBQ), @items : Slice(T)); end

      def self.new(rbq : Pointer(RBQ), items : Pointer(T), size : LibC::SizeT)
        new rbq, Slice(T).new items, size
      end

      delegate :to_unsafe, to: @items

      def [](seq_v) : T
        @items[seq_v & @rbq.value.mask]
      end

      def []=(seq_v, item : T)
        @items[seq_v & @rbq.value.mask] = item
      end

      def copy(range : Range(LibC::SizeT, LibC::SizeT), into dest : Slice(T))
        i = range.begin & mask
        if i + range.end <= @rbq.value.capacity
          # copy range.end items to dest
          dest.copy_from @items + i, count: range.end
        else
          # I'm guessing this has to do with why it's called a "ring" buffer...
          part = rbq.value.capacity - i
          dest.copy_from @items + i, count: part
          @items.copy_to dest + part, count: range.end - part
        end
      end

      def [](range : Range(LibC::SizeT, LibC::SizeT))
        Slice(T).new(LibC.malloc(sizeof(T)), range.size).tap do |slice|
          copy range, into: slice
        end
      end

      def []=(range : Range(LibC::SizeT, LibC::SizeT), src : Slice(T))
        i = range.begin + @rbq.value.mask
        if i + range.end <= @rbq.value.capacity
          src.copy_to @items + i, count: range.end
        else
          part = @rbq.value.capacity
          src.copy_to @items + i, count: range.end
          @items.copy_from src + part, count: range.end
        end
      end
    end
  end
end
