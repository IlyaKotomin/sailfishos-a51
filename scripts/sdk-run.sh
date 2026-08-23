#!/bin/bash
# Drive an interactive Platform SDK session that the user opened in tmux.
#   user:  tmux new -s sdk      then inside it:  sfossdk
#   agent: ~/a51-sfos-port/sdk-run.sh 'command'   [timeout-seconds]
# Types the command into that session, waits for a sentinel, prints new output.
SESSION=${SESSION:-sdk}
CMD=$1
TIMEOUT=${2:-1800}
LOG=$HOME/a51-sfos-port/logs/sdk-session.log

tmux has-session -t "$SESSION" 2>/dev/null || { echo "!! no tmux session '$SESSION'"; exit 2; }
STAMP=$(date +%s%N)
MARK="__DONE_${STAMP}__"

tmux send-keys -t "$SESSION" "$CMD ; echo \"__DO\"\"NE_${STAMP}__ rc=\$?\"" Enter
start=$SECONDS
while [ $((SECONDS-start)) -lt "$TIMEOUT" ]; do
  if tmux capture-pane -p -S -4000 -t "$SESSION" | grep -q "$MARK rc="; then
    tmux capture-pane -p -S -4000 -t "$SESSION" \
      | awk -v m="$MARK" 'index($0,m" rc="){found=1} {buf[NR]=$0} END{for(i=1;i<=NR;i++) print buf[i]}' \
      | tail -60 | tee -a "$LOG"
    exit 0
  fi
  sleep 3
done
echo "!! timed out after ${TIMEOUT}s; last output:"
tmux capture-pane -p -S -60 -t "$SESSION" | tail -30
exit 1
