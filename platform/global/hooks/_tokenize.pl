#!/usr/bin/perl
# _tokenize.pl — the ONE shell-faithful tokenizer for every guard hook.
#
# Why this exists (2026-07-05 method pivot, after 7 reactive Codex rounds): the
# guards used to match REGEX against a command STRING, and there were TWO
# hand-maintained parsers — the git-side `_git_segments` and the writer-side
# lexer in block-file-redirect — that DRIFTED apart (the grammar fuzzer found 6
# leaks living only on the writer surface). A regex cannot model shell execution;
# two regex parsers cannot stay in lockstep. This module replaces both with a
# single quote-state lexer that emits a normalized argv model. Guards then match
# on ARGV TOKENS, not strings — so parity is structural and the audit's A9
# false-positive class (a flag literal inside a `-m` message) cannot recur,
# because a quoted message is exactly one argv token that the guard skips.
#
# THREAT MODEL: these are GUARDRAILS against an agent's accidental/obvious
# mistakes, NOT a sandbox. Shell is Turing-complete (eval, base64|sh, python -c,
# write-then-run always win); the hard boundary is server-side branch protection
# + agents-never-merge + the settings deny-list. So we model the common,
# non-adversarial surface faithfully and accept documented residuals (e.g. a
# newline embedded in a single token is collapsed to a space).
#
# INPUT:  the command string on stdin (already JSON-decoded by _parse-input.sh).
# OUTPUT: one block per simple-command the shell would execute, line-oriented so
#         a token may contain spaces/tabs freely (only newlines are collapsed):
#           C<argv0>   start of a command record; argv0 = resolved command word
#           D<effdir>  effective directory (cd- and `git -C`-tracked); default "."
#           A<token>   one argv token (repeated; the first A equals argv0)
#           R<target>  one write-redirect target (repeated; may appear with empty C)
#
# Everything the old two parsers learned across rounds 1–7 lives here ONCE:
# quote forms ('…' "…" $'…' $"…"), simple-command splitting on unquoted
# ;/&&/||/|/&/newline and ()/{} groups and $(…)/`…`, wrapper-chain resolution
# (env/sudo/xargs/command/nohup/time + opts, bash|sh -c re-lexing, control
# keywords, VAR= assignments, cd, path-qualified/backslash/ANSI-C command words,
# git -c alias expansion), and effective-dir tracking (cd, -C, --git-dir,
# --work-tree).

use strict;
use warnings;

my $src = do { local $/; <STDIN> };
$src = "" unless defined $src;

# ---------------------------------------------------------------------------
# Quote-aware word reader. Consumes a maximal word starting at $i, concatenating
# adjacent quoted/unquoted runs (`--no-ver"ify"` → `--no-verify`, `g"it"` → git),
# and returns ($dequoted_word, $next_index). Stops at unquoted whitespace or an
# unquoted shell operator.
# ---------------------------------------------------------------------------
sub read_dq {   # inside "...", start past the opening quote
  my ($s, $i) = @_; my $n = length $s; my $out = "";
  while ($i < $n) {
    my $c = substr($s, $i, 1);
    if ($c eq '"') { $i++; last; }
    if ($c eq '\\') {
      my $nx = substr($s, $i + 1, 1);
      if ($nx =~ /["\\\$`]/) { $out .= $nx; $i += 2; next; }   # only these are special in "…"
      $out .= '\\'; $i++; next;                                 # keep the backslash
    }
    $out .= $c; $i++;
  }
  return ($out, $i);
}

sub read_ansic {   # inside $'...', start past the $'
  my ($s, $i) = @_; my $n = length $s; my $out = "";
  my %m = (n=>"\n", t=>"\t", r=>"\r", e=>"\e", '\\'=>'\\', "'"=>"'",
           '"'=>'"', a=>"\a", b=>"\b", f=>"\f", v=>"\013", '0'=>"\0");
  while ($i < $n) {
    my $c = substr($s, $i, 1);
    if ($c eq "'") { $i++; last; }
    if ($c eq '\\') {
      my $nx = substr($s, $i + 1, 1);
      $out .= exists $m{$nx} ? $m{$nx} : $nx; $i += 2; next;
    }
    $out .= $c; $i++;
  }
  return ($out, $i);
}

sub read_word {
  my ($s, $i) = @_; my $n = length $s; my $out = "";
  while ($i < $n) {
    my $c = substr($s, $i, 1);
    last if $c =~ /[ \t\n\r]/;
    last if $c =~ /[;|&<>()`]/;
    last if $c eq '$' && substr($s, $i + 1, 1) eq '(';          # $( … ) boundary
    if ($c eq "'") {                                            # '…' literal
      my $j = index($s, "'", $i + 1);
      if ($j < 0) { $out .= substr($s, $i + 1); return ($out, $n); }
      $out .= substr($s, $i + 1, $j - $i - 1); $i = $j + 1; next;
    }
    if ($c eq '"') { my ($seg, $ni) = read_dq($s, $i + 1); $out .= $seg; $i = $ni; next; }
    if ($c eq '$' && substr($s, $i + 1, 1) eq "'") { my ($seg, $ni) = read_ansic($s, $i + 2); $out .= $seg; $i = $ni; next; }
    if ($c eq '$' && substr($s, $i + 1, 1) eq '"') { my ($seg, $ni) = read_dq($s, $i + 2); $out .= $seg; $i = $ni; next; }
    if ($c eq '\\') {                                           # unquoted backslash escape
      my $nx = substr($s, $i + 1, 1);
      if ($nx eq '') { return ($out, $i + 1); }
      $out .= $nx; $i += 2; next;                               # \g → g, `\ ` → space
    }
    $out .= $c; $i++;
  }
  return ($out, $i);
}

# read_word but for a whole string with no operators expected — returns the list
# of words (used to re-lex a `-c` string's command word for alias expansion).
sub words_of {
  my ($s) = @_; my @w; my $i = 0; my $n = length $s;
  while ($i < $n) {
    my $c = substr($s, $i, 1);
    if ($c =~ /[ \t\n\r]/) { $i++; next; }
    my ($w, $ni) = read_word($s, $i); push @w, $w; $i = ($ni > $i ? $ni : $i + 1);
  }
  return @w;
}

# ---------------------------------------------------------------------------
# Scanner: command string → flat item list. Each item is:
#   ['w',   $word]    a word
#   ['sep',  $op]     a simple-command boundary (;, &&, ||, |, &, (, ), {, }, $(, `)
#   ['redir',$target] a write redirect and its target ('>' '>>' '>|' '&>' family)
# Input redirects and fd-dups (2>&1, >&-) are consumed but never emitted.
# ---------------------------------------------------------------------------
sub read_redir_target {
  my ($s, $i) = @_; my $n = length $s;
  while ($i < $n && substr($s, $i, 1) =~ /[ \t]/) { $i++; }
  return ("", $i) if $i >= $n || substr($s, $i, 1) =~ /[;|&<>()`\n\r]/;
  return read_word($s, $i);
}

# Find the end of a command substitution `$( … )`. $i starts just past the `$(`; returns
# ($inner_string, $index_past_matching_close). Balances nested `(`/`$(` and skips quotes /
# backticks so a `)` inside them does not close early. Used to scan a command sub embedded
# in an arithmetic span (where the surrounding `$(( … ))` is otherwise inert).
sub _cmdsub {
  my ($s, $i) = @_; my $n = length $s; my $start = $i; my $depth = 1;
  while ($i < $n) {
    my $c = substr($s, $i, 1);
    if    ($c eq "'") { my $j = index($s, "'", $i + 1); $i = ($j < 0 ? $n : $j + 1); }
    elsif ($c eq '"') { (undef, $i) = read_dq($s, $i + 1); }
    elsif ($c eq '`') { my $j = index($s, '`', $i + 1); $i = ($j < 0 ? $n : $j + 1); }
    elsif ($c eq '$' && substr($s, $i + 1, 1) eq '(') { $depth++; $i += 2; }
    elsif ($c eq '(') { $depth++; $i++; }
    elsif ($c eq ')') { $depth--; $i++; return (substr($s, $start, $i - 1 - $start), $i) if $depth == 0; }
    else  { $i++; }
  }
  return (substr($s, $start, $i - $start), $i);   # unterminated → to end
}

# Scan a DOUBLE-QUOTED region for command substitutions. $i starts just past the opening `"`.
# bash executes `$( … )` / backticks even inside "…", so emit their inner COMMANDS as items
# (single quotes and `\`-escapes are inert). Returns the index just past the closing `"`.
sub _scan_dq {
  my ($items, $s, $i) = @_; my $n = length $s;
  while ($i < $n) {
    my $d = substr($s, $i, 1);
    if ($d eq '\\') { $i += 2; next; }                        # \" \$ \` … — escaped, inert
    if ($d eq '"')  { return $i + 1; }                        # end of the double-quoted run
    if ($d eq '$' && substr($s, $i + 1, 1) eq '(') {
      my ($inner, $ni) = _cmdsub($s, $i + 2);
      push @$items, ['sep', '$('], scan($inner), ['sep', ')']; $i = $ni; next;
    }
    if ($d eq '`') {
      my $j = index($s, '`', $i + 1); $j = $n if $j < 0;
      push @$items, ['sep', '`'], scan(substr($s, $i + 1, $j - $i - 1)), ['sep', '`'];
      $i = ($j < $n ? $j + 1 : $n); next;
    }
    $i++;
  }
  return $i;
}

# Emit command substitutions hidden inside DOUBLE quotes of an already-read word span.
# read_word/read_dq fold `"$( … )"` into opaque word text, but bash still executes it — so
# `echo "$(git push --force)"` / `X="$( … )"` must be scanned (Codex P2). An UNquoted `$(`
# never reaches here (read_word stops at it), so every sub found here is inside quotes;
# single-quoted spans are inert and skipped.
sub _emit_dq_cmdsubs {
  my ($items, $s) = @_; my $n = length $s; my $i = 0;
  while ($i < $n) {
    my $c = substr($s, $i, 1);
    if ($c eq "'") { my $j = index($s, "'", $i + 1); $i = ($j < 0 ? $n : $j + 1); next; }
    if ($c eq '"') { $i = _scan_dq($items, $s, $i + 1); next; }
    $i++;
  }
}

sub scan {
  my ($s) = @_; my @items; my $i = 0; my $n = length $s;
  my @pending;   # heredoc delimiters awaiting their body: [$delim, $dash]
  while ($i < $n) {
    my $c = substr($s, $i, 1);
    if ($c eq ' ' || $c eq "\t") { $i++; next; }
    # An unquoted `#` at a word boundary starts a comment to end-of-line. read_word
    # folds any `#` INSIDE a word (`foo#bar`, quoted `"a#b"`) into that word, so the
    # loop only lands on `#` in true command position — bash's comment rule. This is
    # what keeps a `# <<EOF` from ever queuing a heredoc (outside-review P1).
    if ($c eq '#') { $i++ while $i < $n && substr($s, $i, 1) ne "\n"; next; }
    if ($c eq "\n" || $c eq "\r") {
      push @items, ['sep', ';'];
      $i++;
      $i++ if $c eq "\r" && $i < $n && substr($s, $i, 1) eq "\n";   # CRLF = one terminator
      # A heredoc opener queued on the line just ended pulls the FOLLOWING lines in as
      # BODY (stdin data, never commands) up to the closing delimiter — consumed HERE,
      # inside the quote/comment-aware scanner, so a `<<WORD` that was quoted or in a
      # comment was never queued and cannot swallow real commands (the regex pre-strip's
      # false-NEGATIVE class). One chokepoint, one parser (the whole point of the rewrite).
      while (@pending && $i < $n) {
        my ($d, $dash) = @{$pending[0]};
        my $eol = index($s, "\n", $i); $eol = $n if $eol < 0;
        my $line = substr($s, $i, $eol - $i); $line =~ s/\r$//;
        my $t = $line; $t =~ s/^\t+// if $dash;   # <<- ignores leading TABS on the close
        $i = ($eol < $n ? $eol + 1 : $n);
        shift @pending if $t eq $d;               # close = the delimiter ALONE (bash exact)
      }
      next;
    }
    my $two = substr($s, $i, 2);
    if ($two eq '&&' || $two eq '||') { push @items, ['sep', $two]; $i += 2; next; }
    if ($c eq ';') { push @items, ['sep', ';']; $i++; next; }
    # Arithmetic expansion `$(( … ))` and arithmetic command `(( … ))` are a VALUE / a test,
    # never a command list — and `<<`/`>>`/`<`/`>`/`&`/`|` inside them are C operators, not
    # heredocs/redirects/pipes/backgrounding. bash tells them apart from command-substitution
    # `$( ( …` and nested subshells `( ( …` by the DOUBLED paren with NO space, and rejects a
    # real command inside (`((echo hi))` is a syntax error), so consuming the whole BALANCED
    # span inertly is bash-faithful AND cannot hide a command. Without this, `echo $((1<<2))`
    # (or `(( 1<<2 ))`) is misread as a `1<<2` heredoc opener that swallows the following
    # line's real `git push --force` as heredoc body (Codex P2). Depth starts at 2 (both
    # opening parens); scan to the matching `))`.
    if (($c eq '$' && substr($s, $i + 1, 2) eq '((') || substr($s, $i, 2) eq '((') {
      $i += ($c eq '$' ? 3 : 2);
      my $adepth = 2;                                        # the two opening parens
      while ($i < $n && $adepth > 0) {
        my $ch = substr($s, $i, 1);
        # Nested arithmetic first (so its inner is not mis-scanned as a command).
        if (($ch eq '$' && substr($s, $i + 1, 2) eq '((') || substr($s, $i, 2) eq '((') {
          $i += ($ch eq '$' ? 3 : 2); $adepth += 2; next;
        }
        # A nested command substitution `$( … )` still EXECUTES in bash even inside arithmetic
        # (`$(( $(git push --force) + 1 ))`), so scan its inner COMMANDS rather than dropping
        # them (Codex P2). Its own parens are balanced by _cmdsub, not counted against $adepth.
        if ($ch eq '$' && substr($s, $i + 1, 1) eq '(') {
          my ($inner, $ni) = _cmdsub($s, $i + 2);
          push @items, ['sep', '$('], scan($inner), ['sep', ')'];
          $i = $ni; next;
        }
        if ($ch eq '`') {                                    # backtick command substitution
          my $j = index($s, '`', $i + 1); $j = $n if $j < 0;
          push @items, ['sep', '`'], scan(substr($s, $i + 1, $j - $i - 1)), ['sep', '`'];
          $i = ($j < $n ? $j + 1 : $n); next;
        }
        if ($ch eq "'") { my $j = index($s, "'", $i + 1); $i = ($j < 0 ? $n : $j + 1); next; }  # opaque operand
        if ($ch eq '"') { $i = _scan_dq(\@items, $s, $i + 1); next; }   # "…" runs $() too (Codex P2)
        if    ($ch eq '(') { $adepth++; $i++; next; }
        elsif ($ch eq ')') { $adepth--; $i++; next; }
        $i++;   # inert arithmetic operator / operand char (`<<`, `>>`, digits, +, …)
      }
      next;
    }
    if ($c eq '$' && substr($s, $i + 1, 1) eq '(') { push @items, ['sep', '$(']; $i += 2; next; }
    if ($c eq '`') { push @items, ['sep', '`']; $i++; next; }
    if ($c eq '(') { push @items, ['sep', '(']; $i++; next; }
    if ($c eq ')') { push @items, ['sep', ')']; $i++; next; }
    if ($c eq '{') { my $nx = substr($s, $i + 1, 1); if ($nx eq '' || $nx =~ /[ \t\n\r]/) { push @items, ['sep', '{']; $i++; next; } }
    if ($c eq '}') { my $nx = substr($s, $i + 1, 1); if ($nx eq '' || $nx =~ /[ \t\n\r;&|)]/) { push @items, ['sep', '}']; $i++; next; } }
    # Redirects. Order matters: combined `&>`/`&>>` before the `&` background op,
    # and fd-dup `>&`/`n>&` (not a file write) before plain `>`.
    my $rest = substr($s, $i);
    if ($rest =~ /^&>>?/) { my $op = $&; $i += length $op; my ($t, $ni) = read_redir_target($s, $i); push @items, ['redir', $t] if $t ne ""; $i = $ni; next; }
    if ($rest =~ /^(\d*)>&/) { $i += length($1) + 2; my ($t, $ni) = read_redir_target($s, $i); $i = $ni; next; }   # fd dup — skip
    if ($rest =~ /^(\d*)(>>|>\||>)/) { $i += length($1) + length($2); my ($t, $ni) = read_redir_target($s, $i); push @items, ['redir', $t] if $t ne ""; $i = $ni; next; }
    if ($rest =~ /^(\d*)<<</) { $i += length($1) + 3; my ($t, $ni) = read_redir_target($s, $i); $i = $ni; next; }   # here-string <<< — one word, no body
    if ($rest =~ /^(\d*)<<(-?)/) {                                         # heredoc opener — queue the delimiter; body consumed at the next newline
      $i += length($1) + 2 + length($2);
      $i++ while $i < $n && substr($s, $i, 1) =~ /[ \t]/;                  # `<< WORD` — spaces allowed before the delimiter
      my ($delim, $ni) = read_word($s, $i); $i = ($ni > $i ? $ni : $i + 1);
      push @pending, [$delim, ($2 eq '-')] if $delim ne '';               # quoted `<<'EOF'`/`<<"EOF"` dequoted by read_word (bash matches the unquoted value)
      next;
    }
    if ($rest =~ /^(\d*)</) { $i += length($1) + 1; my ($t, $ni) = read_redir_target($s, $i); $i = $ni; next; }   # plain input redirect — skip target
    if ($c eq '|') { push @items, ['sep', '|']; $i++; next; }
    if ($c eq '&') { push @items, ['sep', '&']; $i++; next; }
    my ($w, $ni) = read_word($s, $i);
    if ($ni > $i) {
      push @items, ['w', $w];
      _emit_dq_cmdsubs(\@items, substr($s, $i, $ni - $i));   # "$( … )" hidden in the word runs too
      $i = $ni;
    }
    else { $i++; }   # defensive: never stall
  }
  return @items;
}

# ---------------------------------------------------------------------------
# Emit. Newlines within a token collapse to a space (guardrail model).
# ---------------------------------------------------------------------------
sub esc { my $x = shift; $x = "" unless defined $x; $x =~ s/[\r\n]+/ /g; return $x; }

sub emit_cmd {
  my ($argv, $effdir, $redirs) = @_;
  my $a0 = @$argv ? $argv->[0] : "";
  print "C" . esc($a0) . "\n";
  print "D" . esc($effdir) . "\n";
  print "A" . esc($_) . "\n" for @$argv;
  print "R" . esc($_) . "\n" for @$redirs;
}

sub emit_redir_only {
  my ($effdir, $redirs) = @_;
  return unless @$redirs;
  print "C\n";
  print "D" . esc($effdir) . "\n";
  print "R" . esc($_) . "\n" for @$redirs;
}

sub _join { my ($base, $p) = @_; return $p if $p =~ m{^/}; return $p if $base eq '.'; return "$base/$p"; }
sub norm  { my $w = shift; $w =~ s{^\\+}{}; $w =~ s{.*/}{}; return $w; }

# Resolve one run of words (+ its redirects) into emitted command block(s),
# threading the cd-tracked cwd via \$cwd. May emit 0 (cd / empty), 1 (normal),
# or many (bash -c "a; b") commands.
sub resolve {
  my ($words, $redirs, $cwdref) = @_;
  my @w = @$words;
  my $cwd = $$cwdref;

  # --- wrapper / control-keyword / assignment stripping ---
  while (@w) {
    my $b = norm($w[0]);
    if ($b =~ /^(?:if|then|elif|else|while|until|do|done|!|time)$/) { shift @w; next; }
    if ($w[0] =~ /^[A-Za-z_][A-Za-z0-9_]*=/) { shift @w; next; }        # VAR=value
    if ($b =~ /^(?:command|builtin|nohup)$/) { shift @w; shift @w while @w && $w[0] =~ /^-/; next; }
    if ($b eq 'sudo') {
      shift @w;
      while (@w && $w[0] =~ /^-/) { my $f = shift @w; shift @w if @w && $f =~ /^-[ugUTRDChp]$/; }
      next;
    }
    if ($b eq 'env') {
      shift @w;
      while (@w && ($w[0] =~ /^-/ || $w[0] =~ /^[A-Za-z_][A-Za-z0-9_]*=/)) {
        my $f = $w[0];
        if ($f eq '-S' || $f eq '--split-string') { shift @w; my $sub = @w ? shift @w : ""; tokenize($sub, $cwd); $$cwdref = $cwd; return; }
        if ($f =~ /^--split-string=(.*)$/s || $f =~ /^-S(.+)$/s) { my $sub = $1; shift @w; tokenize($sub, $cwd); $$cwdref = $cwd; return; }
        shift @w;
        shift @w if @w && ($f eq '-u' || $f eq '--unset' || $f eq '-C' || $f eq '--chdir');
      }
      next;
    }
    if ($b eq 'xargs') {
      shift @w;
      while (@w && $w[0] =~ /^-/) { my $f = shift @w; shift @w if @w && $f =~ /^-[IiEeLlnPsda]$/; }
      next;
    }
    if ($b =~ /^(?:bash|sh|dash|zsh|ksh)$/) {
      my @probe = @w; shift @probe; my $hasc = 0;
      while (@probe && $probe[0] =~ /^-/) { my $f = shift @probe; if ($f =~ /c/) { $hasc = 1; last; } }
      if ($hasc && @probe) { tokenize($probe[0], $cwd); $$cwdref = $cwd; return; }
      last;   # `bash script.sh` etc — treat bash as the command word
    }
    last;
  }

  emit_redir_only($cwd, $redirs), return unless @w;

  # --- cd: moves the shell for subsequent commands (PR #11 R7) ---
  if (norm($w[0]) eq 'cd') {
    shift @w;
    my $dir;
    while (@w) { my $t = shift @w; next if $t eq '--' || $t =~ /^-[LP]+$/; $dir = $t; last; }
    if (defined $dir && $dir ne '' && $dir ne '-') { $cwd = _join($cwd, $dir); $$cwdref = $cwd; }
    emit_redir_only($cwd, $redirs);
    return;
  }

  # --- command word + effective directory + git alias expansion ---
  my $cmd = norm(shift @w);
  my $effdir = $cwd;

  if ($cmd eq 'git' || $cmd eq 'gh') {
    my %alias;
    while (@w) {
      my $t = $w[0];
      if    ($t eq '-C')            { shift @w; my $d = @w ? shift @w : ""; $effdir = _join($cwd, $d); next; }
      elsif ($t =~ /^-C(.+)$/)      { $effdir = _join($cwd, $1); shift @w; next; }
      elsif ($t eq '--git-dir')     { shift @w; my $g = @w ? shift @w : ""; $g =~ s{/\.git/?$}{}; $effdir = ($g eq '' ? '/' : _join($cwd, $g)); next; }
      elsif ($t =~ /^--git-dir=(.*)$/s) { my $g = $1; $g =~ s{/\.git/?$}{}; $effdir = ($g eq '' ? '/' : _join($cwd, $g)); shift @w; next; }
      elsif ($t eq '--work-tree')   { shift @w; my $d = @w ? shift @w : ""; $effdir = _join($cwd, $d); next; }
      elsif ($t =~ /^--work-tree=(.*)$/s) { $effdir = _join($cwd, $1); shift @w; next; }
      elsif ($t eq '-c')            { shift @w; my $kv = @w ? shift @w : ""; $alias{$1} = $2 if $kv =~ /^alias\.([A-Za-z][\w-]*)=(.*)$/s; next; }
      elsif ($t =~ /^-c(.+)$/s)     { my $kv = $1; $alias{$1} = $2 if $kv =~ /^alias\.([A-Za-z][\w-]*)=(.*)$/s; shift @w; next; }
      elsif ($t eq '-R' || $t eq '--repo' || $t eq '--namespace' || $t eq '--exec-path') { shift @w; shift @w if @w; next; }
      elsif ($t =~ /^--(?:repo|namespace|exec-path)=/) { shift @w; next; }
      elsif ($t =~ /^(?:--no-pager|--paginate|--bare|--literal-pathspecs|--no-optional-locks|-P)$/) { shift @w; next; }
      else { last; }
    }
    if (@w && exists $alias{$w[0]}) { my $sub = $alias{shift @w}; unshift @w, words_of($sub); }
  }

  emit_cmd([$cmd, @w], $effdir, $redirs);
}

# tokenize a command string: scan → group runs on separators → resolve each run.
# cwd threads across runs so `cd x && git push` runs in x (PR #11 R7).
sub tokenize {
  my ($s, $cwd) = @_;
  $cwd = "." unless defined $cwd;
  my @items = scan($s);
  my @words; my @redirs;
  my $flush = sub {
    if (@words || @redirs) { resolve(\@words, \@redirs, \$cwd); }
    @words = (); @redirs = ();
  };
  for my $it (@items) {
    if    ($it->[0] eq 'w')     { push @words, $it->[1]; }
    elsif ($it->[0] eq 'redir') { push @redirs, $it->[1]; }
    else                        { $flush->(); }   # any separator ends the run
  }
  $flush->();
}

tokenize($src, ".");
