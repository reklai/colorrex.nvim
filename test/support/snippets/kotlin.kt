class ParseException : Exception()
fun parse(text: String?): Int {
    if (text == null) throw ParseException("empty")
    try { return text.toInt() } catch (err: NumberFormatException) { error("bad") } finally { done = true }
    TODO()
}
fun size(a: String?): Int = a?.length ?: a!!.length
