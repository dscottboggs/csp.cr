require "./rbq/*"

module CSP
  macro atomic_property(expr)
    @{{expr.var}} : {{expr.type}} {% if expr.value %} = {{expr.value}} {% end %}
    def {{expr.var}}
      @{{expr.var}}.get
    end
    def {{expr.var}}=(value)
      @{{expr.var}}.set value
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
  end
end
