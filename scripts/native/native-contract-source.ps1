# C++ translation phase 2 splices lines before recognizing comments. Preserve
# literals (including raw strings) so comment markers inside them remain code.
function Remove-NativeCppComments([string]$Text) {
    $spliced = [regex]::Replace($Text, '\\\r?\n', '')
    $tokens = '(?s)R"(?<delimiter>[^\s()\\]{0,16})\(.*?\)\k<delimiter>"|"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*''|(?<comment>//[^\r\n]*|/\*.*?\*/)'
    return [regex]::Replace($spliced, $tokens, [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        if ($match.Groups['comment'].Success) {
            # Keep tokens separated and retain line breaks for diagnostics.
            return [regex]::Replace($match.Value, '[^\r\n]', ' ')
        }
        return $match.Value
    })
}
