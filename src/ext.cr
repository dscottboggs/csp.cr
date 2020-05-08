abstract struct Number
  def to_size_t
    LibC::SizeT.new self
  end
end
