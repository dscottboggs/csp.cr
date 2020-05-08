require "./ext"

module CSP
  # This is padded because x64 architectures use 64-byte cache lines.
  #
  # TODO: if there are modern architectures (ARM? RISCV? x86?) which don't
  # use 64-byte cache-lines, this value should be changed to the appropriate
  # cache-line size, minus the 8 bytes consumed by the UInt64 on 32-bit systems
  # or the 4 bytes consumed by a UInt32 on 32-bit systems.
  {% begin %}
  PADDING_SIZE = {% if flag? :bits32 %} 60 {% else %} 56 {% end %}
  {% end %}
  alias PaddingT = UInt8[PADDING_SIZE]
end

macro soft_mbarr
  asm("" ::: "memory")
end

macro exp(num)
  %exp = 0
  if {{num}} > 0
    %tmp = {{num}}
    until %tmp == 1
      %exp += 1
      %tmp >>= 1
    end
    %exp += 1 if (1 << %exp) != {{num}}
  end
end

macro atomic_property(expr)
  @{{expr.var}} : {{expr.type}} {% if expr.value %} = {{expr.value}} {% end %}
  def {{expr.var}}
    @{{expr.var}}.get
  end
  def {{expr.var}}=(value)
    @{{expr.var}}.set value
  end
end
