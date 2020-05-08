module CSP
  abstract class RBQ(T)
    private struct Items(T)
      @items : Slice(T)
      @capacity : Pointer(LibC::SizeT)
      @mask : Pointer(LibC::SizeT)

      def self.new(capacity, mask)
        new capacity, mask, Slice(T).new capacity.value
      end
      def initialize(@capacity, @mask, @items)
        raise "null capacity" if @capacity.null?
        raise "null mask" if @mask.null?
      end

      delegate :to_unsafe, to: @items

      # Retrieve a single value of self from the given index.
      def [](index) : T
        @items[index.to_size_t & @mask.value]
      end

      # Set a single value on self at the given index.
      def []=(index, item : T)
        @items[index.to_size_t & @mask.value] = item
      end

      # Copy the given index range on self into the given, already allocated slice.
      def copy(range : Range(LibC::SizeT, LibC::SizeT), into dest : Slice(T))
        i = range.begin & @mask.value
        if i + range.end <= @capacity.value
          # copy range.end items to dest
          dest.copy_from @items.to_unsafe + i, count: range.end
        else
          # I'm guessing this has to do with why it's called a "ring" buffer...
          part = @capacity.value - i
          dest.copy_from @items.to_unsafe + i, count: part
          @items.copy_to dest.to_unsafe + part, count: range.end - part
        end
      end

      # Copy the given index range on self into the given, already allocated slice.
      def copy(range : Range(Number, Number), into dest : Slice(T))
        copy as_size_ts(range), into: dest
      end

      # Return a new Slice of the given index range of self.
      def [](range : Range(LibC::SizeT, LibC::SizeT))
        Slice(T).new(LibC.malloc(sizeof(T)), range.size).tap do |slice|
          copy range, into: slice
        end
      end


      # Return a new Slice of the given index range of self.
      def [](range : Range(Number, Number))
        self[as_size_ts range]
      end

      # Assign the values of slice to the given index range on self.
      def []=(range : Range(LibC::SizeT, LibC::SizeT), src : Slice(T)) : Nil
        i = range.begin + @mask.value
        if i + range.end <= @capacity.value
          src.copy_to @items.to_unsafe + i, count: range.end
        else
          part = @capacity.value
          src.copy_to @items.to_unsafe + i, count: range.end
          @items.copy_from src.to_unsafe + part, count: range.end
        end
      end

      # Assign the values of slice to the given index range on self.
      def []=(range : Range(Number, Number), src : Slice(T)) : Nil
        self[as_size_ts range] = src
      end

      private def as_size_ts(range)
        if range.exclusive?
          range.begin.to_size_t..range.end.to_size_t
        else
          range.begin.to_size_t...range.end.to_size_t
        end
      end
    end
  end
end
