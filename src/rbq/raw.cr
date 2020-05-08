require "../rbq"

module CSP
  # Raw (not thread safe) RBQ implementation.
  class Raw(T) < RBQ(T)
    def initialize(capacity_exponent)
      @capacity = 1 << capacity_exponent
      @mask = cap - 1
      @items : Items(T) = Items(T).new self, @capacity
    end

    property items,
      capacity : LibC::SizeT,
      mask : LibC::SizeT,
      slow = 0_u64,
      fast = 0_u64

    # Returns true if successful
    def push?(item : T) : Bool
      !!if size < capacity
        items[@slow] = item
        @slow += 1
      end
    end

    # Returns true if successful
    def push_front?(item : T) : Bool
      !!if size < capacity
        @items[@slow -= 1] = item
      end
    end

    def pop? : T?
      if size > 0
        @items[@slow].tap { @slow += 1 }
      end
    end

    def grow? : Bool
      cap = @capacity << 1
      items = @items.to_unsafe.realloc size: cap
      !!unless items.null?
        @items = Items(T).new items
        @capacity = cap
      end
    end

    def size
      fast - slow
    end
  end
end
