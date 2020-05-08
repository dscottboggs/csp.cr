require "./common"
require "./rbq/items"

module CSP

  # RBQ is a reimplementation of `libcsp/rbq.h`, which implements a high performance
  # lock-freed ring buffer queue inspired by Disruptor.

  # It implements five kinds of ring buffer queue. i.e,
  # - RBQ::Raw:  Raw                               Ring Buffer Queue.
  # - RBQ::SS:   Single   writer  Single   reader  Ring Buffer Queue.
  # - RBQ::SM:   Single   writer  Multiple readers Ring Buffer Queue.
  # - RBQ::MS:   Multiple writers Single   reader  Ring Buffer Queue.
  # - RBQ::MM:   Multiple writers Multiple readers Ring Buffer Queue.

  # `RBQ::Raw` is just a traditional ring buffer and it's not thread-safe.
  # `SS`, `SM`, `MS` and `MM` are thread-safe, you can use them in different
  # processes.
  abstract class RBQ(T)
    abstract def items : Items(T)
    abstract def push?(item : T) : Bool
    abstract def pop? : T?
    abstract def capacity : LibC::SizeT
    abstract def size : LibC::SizeT
  end
end

require "./rbq/*"
