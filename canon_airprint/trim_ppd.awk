# Keep only the paper sizes listed in KEEP (comma separated) in a PPD file,
# and make the first one the default. Usage:
#   awk -v KEEP="Letter,Legal" -f trim_ppd.awk in.ppd > out.ppd
BEGIN {
  n = split(KEEP, k, ",")
  for (i = 1; i <= n; i++) keep[k[i]] = 1
  def = k[1]
  skipping = 0
}
# Inside a multi-line value of an entry we're dropping: skip until *End.
skipping {
  if ($0 ~ /^\*End/) skipping = 0
  next
}
/^\*(PageSize|PageRegion|ImageableArea|PaperDimension) / {
  key = $2
  sub(/[\/:].*/, "", key)
  if (!(key in keep)) {
    # Value opened a quote that doesn't close on this line -> multi-line.
    q = gsub(/"/, "\"")
    if (q % 2 == 1) skipping = 1
    next
  }
}
/^\*Default(PageSize|PageRegion|ImageableArea|PaperDimension):/ {
  sub(/:.*/, ": " def)
}
{ print }
