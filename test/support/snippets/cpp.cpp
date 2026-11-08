int parse(const char *text) {
  if (text == nullptr) throw std::runtime_error("empty");
  try { return std::stoi(text); } catch (const std::invalid_argument &err) { throw; }
  return true ? 3 : 0;
}
