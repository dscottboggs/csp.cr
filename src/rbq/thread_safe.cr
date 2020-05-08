require "../rbq"

module CSP
  abstract class RBQ(T)
    {% for writer in {:S, :M} %}
    {% for reader in {:S, :M} %}
    class {{writer.id}}{{reader.id}}(T) < RBQ(T)

      def initialize(capacity_exponent : Int)
        @capacity = LibC::SizeT.new 1 << capacity_exponent
        @mask = LibC::SizeT.new @capacity - 1
        @slow = {{writer.id}}PTR.new @capacity
        @fast = {{reader.id}}PTR.new @capacity
        @items = Items(T).new pointerof(@capacity), pointerof(@mask)
      end # def

      getter capacity, items, mask, slow, fast

      def size
        capacity
      end

      # Try to push an item onto the RBQ. Returns true on success.
      #
      # https://github.com/shiyanhui/libcsp/blob/ea0c5a41d7b518027019e7eaad7e575f7cc45d30/src/rbq.h#L298-L319
      def push?(item : T) : Bool
        sbarr = @slow.barr
        fnext = @fast.next

        if sbarr + @capacity <= fnext
          sbarr = @slow.update_barr @mask
          return false if sbarr + @capacity <= fnext
        end # if

        if @fast.next_rsv fnext.to_u64, 1_u64
          @items[fnext] = item
          @fast.mark_available fnext, @mask
          true
        end # if
        false
      end # def

      # This will block execution, looping until there is space on the queue to push.
      #
      # https://github.com/shiyanhui/libcsp/blob/ea0c5a41d7b518027019e7eaad7e575f7cc45d30/src/rbq.h#L321-L346
      def push(item : T) : Void
        loop do
          sbarr = @slow.barr
          fnext = @fast.next
          if sbarr + @capacity <= fnext
            sbarr = @slow.update_barr @mask
            if sbarr + @capacity > fnext
              if @fast.next_rsv fnext, 1
                @items[fnext] = item
                @fast.mark_available fnext, @mask
              end
              return
            end
            CSP.yield
          end # if
        end # loop
      end # def

      # Pop a value off the queue if there is one available. Returns nil otherwise.
      #
      # https://github.com/shiyanhui/libcsp/blob/ea0c5a41d7b518027019e7eaad7e575f7cc45d30/src/rbq.h#L348-L369
      def pop? : T?
        snext = @slow.next
        fbarr = @fast.barr
        return if snext >= fbarr
        if @slow.next_rsv snext, 1_u64
          @slow.mark_available snext, @mask
          @items[snext]
        end # if
      end # def

      # Pop a value off the queue if there is one available. If not, wait until there is one,
      # yielding execution between each check.
      #
      # https://github.com/shiyanhui/libcsp/blob/ea0c5a41d7b518027019e7eaad7e575f7cc45d30/src/rbq.h#L371-L395
      def pop : T
        loop do
          snext = @slow.next
          fbarr = @fast.barr

          if snext >= fbarr
            @fast.update_barr @mask
            if snext < fbarr
              if @slow.next_rsv snext, 1
                @slow.mark_available snext, @mask
                return @items[snext]
              end
            end
            CSP.yield
          end # if
        end # loop
      end # def

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

          if sbarr + @capacity < fnext + values.size
            sbarr = @slow.update_barr @mask
            return false if sbarr + @capacity < fnext + values.size
          end # if

          if @fast.next_rsv fnext.to_u64, values.size.to_u64
            @items[fnext..values.size] = values
            @fast.mark_available fnext, fnext + values.size, @mask
            true
          else
            false
          end # if
        end # case
      end # def

      # Push multiple values onto the queue, waiting until there is room if necessary.
      #
      # https://github.com/shiyanhui/libcsp/blob/ea0c5a41d7b518027019e7eaad7e575f7cc45d30/src/rbq.h#L425-L473
      def push(values : Slice(T)) : Nil
        if values.size > 1
          chunk = values.size < @capacity ? values.size : @capacity

          while values.size > 0
            sbarr = @slow.barr
            fnext = @fast.next

            if (sbarr + @capacity) < (fnext + chunk)
              sbarr = @slow.update_barr @mask
              next push_items if sbarr + @capacity >= fnext + chunk
              if chunk == 1
                CSP.yield
              else
                chunk >>= 1
              end # if
              next
            end # if
            push_items
          end # while
        elsif values.size == 1
          push values.first
        end # if
      end # def

      private macro push_items
        if @fast.next_rsv fnext.to_u64, chunk.to_u64
          if chunk > 1
            @items[fnext..chunk] = values
            @fast.mark_available fnext, fnext + chunk, @mask
          else
            @items[fnext] = values.first
            @fast.mark_available fnext, @mask
          end # if
          values += chunk
        end # if
      end

      # Pop as many values as are available onto the given slice, returning the
      # count of values added to the slice.
      #
      # https://github.com/shiyanhui/libcsp/blob/ea0c5a41d7b518027019e7eaad7e575f7cc45d30/src/rbq.h#L475-L511
      def pop?(values : Slice(T)) : LibC::SizeT
        case values.size.to_u64
        when 0 then 0_u64
        when 1
          if popped = pop?
            values[0] = popped
            1_u64
          else
            0_u64
          end # if
        when .< 0 then raise "Crystal's Slice#size is dumb"
        else
          snext = @slow.next
          fbarr = @fast.barr
          fbarr = @fast.update_barr @mask if snext >= fbarr
          return 0_u64 if snext >= fbarr

          len = fbarr - snext
          len = values.size if values.size < len

          if @slow.next_rsv snext.to_u64, len.to_u64
            if len > 1
              @items.copy snext..len, into: values
              @slow.mark_available snext, snext + len, @mask
            else
              values[0] = @items[snext]
              @slow.mark_available snext, @mask
            end # if
            len.to_u64
          else
            0_u64
          end # if
        end # case
      end # def

      # Allocate a slice of `n` `T`s and try to pop as many values as are
      # available into it. If the slice is filled, it will be returned. If it's
      # partially filled, the slice will be shrunk to the number of valid values
      # before being returned. This means that if there are no available values,
      # the empty `Slice(T)` will be returned.
      #
      # https://github.com/shiyanhui/libcsp/blob/ea0c5a41d7b518027019e7eaad7e575f7cc45d30/src/rbq.h#L475-L511
      def pop?(n : LibC::SizeT) : Slice(T)
        ptr = GC.malloc(n * sizeof(T)).as Pointer(T)
        slice = Slice(T).new ptr, n
        popped_count = pop? slice
        slice[..popped_count]
      end # def

      def pop(n : LibC::SizeT) : Slice(T)
        ptr = GC.malloc(n * sizeof(T)).as Pointer(T)
        slice = Slice(T).new ptr, n
        pop slice
      end # def

      def pop(values : Slice(T)) : Nil
        return if values.size < 1
        return values[0] = pop if values.size == 1
        while values.size > 0
          snext = @slow.next
          fbarr = @fast.barr
          if snext >= fbarr
            fbarr = @fast.update_barr @mask
            # this   \/ condition is inverted to avoid the GOTO
            if snext >= fbarr
              CSP.yield
              next
            end # if
          end # if
          # the pop_items: label was here in the C code
          len : UInt64 = fbarr - snext
          len = values.size.to_u64 if values.size < len
          if @slow.next_rsv snext, len
            if len > 1
              @items.copy snext..len, into: values
              @slow.mark_available snext, @mask
            else
              values[0] = @items[snext]
              @slow.mark_available snext, @mask
            end # if
            values += len
          end # if
        end # while
      end # def
    end # class
    {% end %}
    {% end %}
  end
end
