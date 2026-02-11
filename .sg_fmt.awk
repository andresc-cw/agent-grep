FNR==1 { sid=""; agent=""; proj=""; pname=""; dt=""; slug=""; in_fm=1 }
in_fm && /^---$/ && FNR>1 { in_fm=0; next }
in_fm && /^session_id: / { sid=substr($0,13) }
in_fm && /^agent: / { agent=substr($0,8) }
in_fm && /^project: / { proj=substr($0,10) }
in_fm && /^project_name: / { pname=substr($0,15) }
in_fm && /^date: / { dt=substr($0,7,10) }
in_fm && /^slug: / { slug=substr($0,7) }
ENDFILE {
  if (agent=="claude" && slug!="" && slug!="untitled") dn=slug; else dn=substr(sid,1,12)"..."
  printf "%s\t%s\t%s\t[%s] %-20s %s  %s\n", sid, agent, proj, agent, pname, dt, dn
}
