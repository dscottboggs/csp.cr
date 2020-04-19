require "../rbq"

module CSP
  abstract struct RBQ
    {% for writer in {:S, :M} %}
      {% for reader in {:S, :M} %}
        alias {{writer.id}}{{reader.id}}(T, I) = ThreadSafeRBQ(T, I, {{writer.id}}PTR, {{reader.id}}PTR)
      {% end %}
    {% end %}

    struct ThreadSafe(T, I, R, W) < RBQ
      property items : Items(T, I),
        capacity : LibC::SizeT,
        mask : LibC::SizeT,
        slow : W,
        fast : R

      def self.new(capacity_exponent : LibC::SizeT)
        @capacity = 1 << capacity_exponent
        @mask = @capacity - 1
        @slow = W.new @capacity
        @fast = R.new @capacity
        @items = Items(T, I).new self, @capacity
      end

      # Try to push an item onto the RBQ. Returns true on success.
      #
      # https://github.com/shiyanhui/libcsp/blob/ea0c5a41d7b518027019e7eaad7e575f7cc45d30/src/rbq.h#L298-L319
      def push?(item : T) : Bool
        sbarr = @slow.barr
        fnext = @fast.next

        if sbarr + @capacity <= fnext
          sbarr = @slow.barr_update @mask
          return false if sbarr + @capacity <= fnext
        end

        if @fast.next_rsv fnext, 1
          @items[fnext] = item
          @fast.mark_available fnext, @mask
          true
        end
        false
      end

      # This will block execution, looping until there is space on the queue to push.
      #
      # TODO yield execution
      #
      # https://github.com/shiyanhui/libcsp/blob/ea0c5a41d7b518027019e7eaad7e575f7cc45d30/src/rbq.h#L321-L346
      def push(item : T)
        loop do
          sbarr = @slow.barr
          fnext = @fast.next
          if sbarr + @capacity <= fnext
            sbarr = @slow.update_barr @mask
            return _rbq_push_item if sbarr + @capacity > fnext
            # TODO yield??
          end
        end
      end

      # Pop a value off the queue if there is one available. Returns nil otherwise.
      #
      # https://github.com/shiyanhui/libcsp/blob/ea0c5a41d7b518027019e7eaad7e575f7cc45d30/src/rbq.h#L348-L369
      def pop? : T?
        snext = @slow.next
        fbarr = @fast.barr
        return false if snext >= fbarr
        if next_rsv snext, 1
          @slow.mark_available snext, @mask
          @items[snext]
        end
      end

      # Pop a value off the queue if there is one available. If not, wait until there is one,
      # yielding execution between each check.
      #
      # https://github.com/shiyanhui/libcsp/blob/ea0c5a41d7b518027019e7eaad7e575f7cc45d30/src/rbq.h#L371-L395
      def pop : T
        loop do
          snext = @slow.next
          fbarr = @fast.barr

          if snext >= fbarr
            @fast.barr_update @mask
            return _rbq_pop_item if sbarr < fbarr
            # TODO yield??
          end
        end
      end
    end

    # Try to push multiple values onto the queue. Returns true if successful.
    #
    # In the case where the empty Slice(T) is passed, true is returned and
    # nothing else happens.
    #
    # https://github.com/shiyanhui/libcsp/blob/ea0c5a41d7b518027019e7eaad7e575f7cc45d30/src/rbq.h#L397-L423
    def push?(values : Slice(T)) : Bool
      case values.size
      when 0    then true
      when 1    then push? values.first
      when .< 0 then raise "Crystal's Slice#size is dumb"
      else
        sbarr = @slow.barr
        fnext = @fast.next

        if sbarr + @cap < fnext + values.size
          sbarr = @slow.update_barr @mask
          return false if sbar + @cap < fnext + values.size
        end

        if @fast.next_rsv fnext, values.size
          @items[fnext..values.size] = values
          @fast.markm_available fnext, fnext + values.size, @mask
          true
        else
          false
        end
      end
    end

    # Push multiple values onto the queue, waiting until there is room if necessary.
    #
    # https://github.com/shiyanhui/libcsp/blob/ea0c5a41d7b518027019e7eaad7e575f7cc45d30/src/rbq.h#L425-L473
    def push(values : Slice(T)) : Bool
      if values.size > 1
        chunk = values.size < @capacity ? value.size : @capacity

        while values.size > 0
          sbarr = @slow.barr
          fnext = @fast.next

          if (sbarr + @capacity) < (fnext + chunk)
            sbarr = @slow.barr_update @mask
            if sbarr + @capacity >= fnext + chunk
              if next_rsv fnext, chunk
                if chunk > 1
                  # TODO shouldn't this  \/ be "= values"?
                  @items[fnext..chunk] = values
                  @fast.markm_available fnext, fnext + chunk, @mask
                else
                  @items[fnext] = values.first
                  @items.mark_available fnext, @mask
                end
                values += chunk
              end
              next
            end
            if chunk != 1
              chunk >>= 1
            else
              # TODO CSP.yield
            end
          end
        end
      elsif values.size == 1
        push values.first
      end
    end

    # Pop as many values as are available onto the given slice, returning the
    # count of values added to the slice.
    #
    # https://github.com/shiyanhui/libcsp/blob/ea0c5a41d7b518027019e7eaad7e575f7cc45d30/src/rbq.h#L475-L511
    def pop?(values : Slice(T)) : LibC::PtrdiffT
      case values.size
      when 0 then 0
      when 1
        if popped = pop?
          values[0] = popped
          1
        end
      when .< 0 then raise "Crystal's Slice#size is dumb"
      else
        snext = @slow.next
        fbarr = @fast.barr
        fbarr = @fast.barr_update @mask if snext >= fbarr
        return 0 if snext >= fbarr

        len = fbarr - snext
        len = values.size if values.size < n

        if @slow.next_rsv snext, len
          if len > 1
            @items.copy snext..len, into: values
            @slow.markm_available snext, snext + len, @mask
          else
            values[0] = @items[snext]
            @slow.mark_available snext, @mask
          end
          len
        else
          0
        end
      end
    end

    # Allocate a slice of `n` `T`s and try to pop as many values as are
    # available into it. If the slice is filled, it will be returned. If it's
    # partially filled, the slice will be shrunk to the number of valid values
    # before being returned. This means that if there are no available values,
    # the empty `Slice(T)` will be returned.
    #
    # https://github.com/shiyanhui/libcsp/blob/ea0c5a41d7b518027019e7eaad7e575f7cc45d30/src/rbq.h#L475-L511
    def pop?(n : LibC::PtrdiffT) : Slice(T)
      ptr = GC.malloc(n * sizeof(T)).as Pointer(T)
      slice = Slice(T).new ptr, n
      popped_count = pop? slice
      slice[..popped_count]
    end

    def pop(n : LibC::PtrdiffT) : Slice(T)
      ptr = GC.malloc(n * sizeof(T)).as Pointer(T)
      slice = Slice(T).new ptr, n
      pop slice
    end

    def pop(values : Slice(T)) : Nil
      return if values.size < 1
      return values[0] = pop if values.size == 1
      while n > 0
        snext = @slow.next
        fbarr = @fast.barr
        if snext >= fbarr
          fbarr = @fast.barr_update @mask
          if snext >= fbarr
            # CSP.yield TODO
            next
          end
        end
        # the pop_items: label was here in the C code
        len = fbarr - snext
        len = values.size if values.size < len
        if @slow.next_rsv snext, len
          if len > 1
            @items.copy snext..len, into: values
            @slow.mark_available snext, @mask
          else
            values[0] = @items[snext]
            @slow.mark_available snext, @mask
          end
          values += len
        end
      end
    end

    macro _rbq_push_item
      if @fast.next_rsv fnext, 1
        @items[fnext] = item
        @fast.mark_available fnext, @mask
      end
    end

    macro _rbq_pop_item
      if @slow.next_rsv snext, 1
        @slow.mark_available snext, @mask
        @items[snext]
      end
    end
  end
end
