require "../rbq"

module CSP
  # Raw (not thread safe) RBQ implementation.
  struct Raw(T, I) < RBQ
    def initialize(capacity_exponent)
      @capacity = 1 << capacity_exponent
      @mask = cap - 1
      @items : Items(T, I) = Items(T, I).new self, @capacity
    end

    property items,
      capacity : LibC::SizeT,
      mask : LibC::SizeT,
      slow = 0_u64,
      fast = 0_u64

    # Returns true if successful
    def try_push(item : T) : Bool
      !!if size < capacity
        items[@slow] = item
        @slow += 1
      end
    end

    # Returns true if successful
    def try_push_front(item : T) : Bool
      !!if size < capacity
        @items[@slow -= 1] = item
      end
    end

    def try_pop : T?
      if size > 0
        @items[@slow].tap { @slow += 1 }
      end
    end

    def try_grow
      cap = @capacity << 1
      items = @items.to_unsafe.realloc size: cap
      unless items.null?
        @items = Items(T, I).new items
        @capacity = cap
      end
    end

    def size
      fast - slow
    end
  end
end
