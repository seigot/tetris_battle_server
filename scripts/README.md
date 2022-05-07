# usage

```
# 本番の場合
nohup bash do_battle.sh &

# ログ出力を無効にする場合(ログサイズが気になる場合)
nohup bash do_battle.sh >/dev/null 2>&1 &

# ログを確認する場合
tail -f nohup.out
```
# prepare

https://github.com/seigot/tetris_score_server/tree/main/scripts
