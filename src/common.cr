module CSP
  macro soft_mbarr
    asm("" ::: "memory")
  end

  macro swap(a, b)
    b, a = a, b
  end

  macro exp(num)
    %exp = 0
    if {{num}} > 0
      tmp = {{num}}
      until tmp == 1
        %exp += 1
        tmp >>= 1
      end
      %exp += 1 if (1 << %exp) != num
    end
  end
end
