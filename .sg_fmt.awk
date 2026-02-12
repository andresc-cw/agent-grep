BEGIN {
  esc=sprintf("%c",27)
  reset=esc "[0m"
  claude_tag=esc "[1;38;5;214m[claude]" reset
  codex_tag=esc "[1;38;5;45m[codex]" reset
}

FNR==1 { sid=""; agent=""; proj=""; pname=""; dt_raw=""; slug=""; in_fm=1 }
in_fm && /^---$/ && FNR>1 { in_fm=0; next }
in_fm && /^session_id: / { sid=substr($0,13) }
in_fm && /^agent: / { agent=substr($0,8) }
in_fm && /^project: / { proj=substr($0,10) }
in_fm && /^project_name: / { pname=substr($0,15) }
in_fm && /^date: / { dt_raw=substr($0,7) }
in_fm && /^slug: / { slug=substr($0,7) }
ENDFILE {
  tag="[" agent "]"
  if (proj=="") proj="unknown"
  if (pname=="") pname="unknown"
  if (dt_raw=="" || dt_raw=="unknown") { dt_show="unknown"; dt_sort="0000-00-00T00:00:00Z" }
  else {
    dt_show=substr(dt_raw,1,10)
    dt_sort=dt_raw
    if (length(dt_sort)==10) dt_sort=dt_sort "T00:00:00Z"
  }
  if (agent=="claude") tag=claude_tag
  else if (agent=="codex") tag=codex_tag
  if (agent=="claude" && slug!="" && slug!="untitled") dn=slug; else dn=substr(sid,1,12)"..."
  printf "%s\t%s\t%s\t%s\t%s\t%s %-20s %s  %s\n", sid, agent, proj, pname, dt_sort, tag, pname, dt_show, dn
}
