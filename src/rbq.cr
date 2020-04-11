module CSP
  macro atomic_property(expr)
    @{{expr.var}} : {{expr.type}} {% if expr.value %} = {{expr.value}} {% end %}
    def {{expr.var}}
      @{{expr.var}}.get
    end
    def {{expr.var}}=(value)
      @{{expr.var}} = value
    end
  end

  abstract struct RBQ
    abstract def initialize
    abstract def items
    abstract def capacity
    abstract def try_push
    abstract def try_push_front
    abstract def try_pop
    abstract def try_grow
    abstract def size

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

    # what is SPTR?
    struct SPTR
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
      def update_barr(x)
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
      # can this be void?
      def next_rsv(current, n)
        barr.set current + n
        true
      end
    end

    # what is MPTR? multiple pointer?
    struct MPTR
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

    struct Items(T, I)
      @rbq : Pointer(RBQ(T, I))
      @items : Slice(T)

      def self.new(rbq : Pointer(RBQ(T, I)), capacity : LibC::SizeT)
        new rbq, Slice(T).new(capacity)
      end

      def initialize(@rbq : Pointer(RBQ(T, I)), @items : Slice(T)); end

      def self.new(rbq : Pointer(RBQ(T, I)), items : Pointer(T), size : LibC::SizeT)
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

  struct RBQ::Raw(T, I) < RBQ
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

  # {% for writer in {:S, :M} %}
  #   {% for reader in {:S, :M} %}
  #   struct RBQ::{{writer.id}}{{reader.id}}(T)
  #     property items : Slice(T),
  #       capacity : LibC::SizeT,
  #       mask : LibC::SizeT,
  #       slow : Pointer(),
  #       fast : Pointer()
  #     def self.new(LibC.SizeT)

  #     end
  #   end
  #   {% end %}
  # {% end %}
end
