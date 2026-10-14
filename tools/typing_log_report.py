#!/usr/bin/env python3
"""分析 lua/typing_log.lua 记下的日志，找出"打错又删掉重打"的模式。

用法： python3 -I tools/typing_log_report.py [日志目录，默认 ~/Library/Rime] [--days N]

输出：
  1. 纠错序列：上屏 A -> 若干退格 -> 再上屏 B（间隔不超过 GAP 秒），按"码的差异类型"归类
  2. 同一对 (A的码 -> B的码) 出现的次数，次数多的就是值得优化的点
  3. swap_fix 的命中和误伤（自动纠正后又被删掉重打）
  4. 敲码中途退格最多的码
"""
import collections, glob, json, os, sys, time

GAP = 30  # 上屏之间超过这么多秒，就不当作同一次纠错

LEFT, RIGHT = set("',.pyaoeui;qjkx"), set("fgcrldhtnsbmwvz")


def hand(c):
    return "L" if c in LEFT else "R" if c in RIGHT else "?"


def classify(a, b):
    """a 是被删掉的那次敲的码，b 是重打的码"""
    if a == b:
        return "同码另选候选"
    if len(a) == len(b):
        diff = [i for i in range(len(a)) if a[i] != b[i]]
        if len(diff) == 2 and diff[1] == diff[0] + 1 and a[diff[0]] == b[diff[1]] and a[diff[1]] == b[diff[0]]:
            i = diff[0]
            cross = hand(a[i]) != hand(a[i + 1])
            return f"相邻换位({'左右手' if cross else '同手'}, 第{i + 1}、{i + 2}键)"
        if len(diff) == 1:
            return f"错一个键(第{diff[0] + 1}键)"
        return "多个键不同"
    return "码长不同"


def load(d, days):
    events = []
    cutoff = time.time() - days * 86400 if days else 0
    for f in sorted(glob.glob(os.path.join(d, "typing_log.*.jsonl"))):
        try:
            fh = open(f, encoding="utf-8")
        except PermissionError:
            sys.exit(f"日志是只写的（0200），先 chmod u+r {os.path.dirname(f)}/typing_log.*.jsonl，看完再 chmod u-r 回去")
        with fh:
            for line in fh:
                try:
                    ev = json.loads(line)
                except ValueError:
                    continue
                if ev.get("ts", 0) >= cutoff:
                    events.append(ev)
    events.sort(key=lambda e: e.get("ts", 0))  # sort 是稳定的，同一秒内保持写入顺序
    return events


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    days = 0
    if "--days" in sys.argv:
        days = int(sys.argv[sys.argv.index("--days") + 1])
        args = [a for a in args if a != str(days)]
    d = os.path.expanduser(args[0] if args else "~/Library/Rime")
    ev = load(d, days)
    if not ev:
        print("没有日志：", d)
        return
    commits = [e for e in ev if e["e"] == "commit"]
    print(f"事件 {len(ev)} 条，上屏 {len(commits)} 次，时间 {time.strftime('%F %T', time.localtime(ev[0]['ts']))} ~ "
          f"{time.strftime('%F %T', time.localtime(ev[-1]['ts']))}\n")

    # 1. 纠错序列
    fixes = []
    last, bs = None, 0
    for e in ev:
        if e["e"] == "commit":
            if last and bs and e["ts"] - last["ts"] <= GAP and e["text"] != last["text"]:
                fixes.append((last, e, bs))
            last, bs = e, 0
        elif e["e"] == "bs" and not e.get("composing") and last:
            bs += 1
        elif e["e"] == "bs" and e.get("composing"):
            pass
        elif e["e"] == "swap_fix":
            pass
        else:
            last, bs = None, 0 if e["e"] == "cancel" else bs
    print(f"== 纠错序列（上屏后退格再重打）：{len(fixes)} 次")
    kinds = collections.Counter()
    pairs = collections.Counter()
    for a, b, n in fixes:
        kinds[classify(a.get("code", ""), b.get("code", ""))] += 1
        pairs[(a["text"], a.get("code", ""), b["text"], b.get("code", ""))] += 1
    for k, v in kinds.most_common():
        print(f"  {v:>4}  {k}")
    print("\n== 出现最多的 (打出→改成)：")
    for (at, ac, bt, bc), v in pairs.most_common(30):
        print(f"  {v:>3}x  {at}({ac}) -> {bt}({bc})   [{classify(ac, bc)}]")

    # 2. swap_fix 命中与误伤
    hits = [i for i, e in enumerate(ev) if e["e"] == "swap_fix"]
    if hits:
        bad = 0
        print(f"\n== swap_fix 触发 {len(hits)} 次")
        for i in hits:
            s = ev[i]
            nxt = next((e for e in ev[i + 1:i + 6] if e["e"] == "commit"), None)
            if not nxt:
                continue
            j = ev.index(nxt)
            undone = any(x["e"] == "bs" and not x.get("composing") for x in ev[j + 1:j + 3])
            if undone and nxt["text"] == s.get("to"):
                bad += 1
                print(f"  可能误伤: {s['code']} {s.get('from')} -> {s['to']} 之后被删掉了")
        print(f"  疑似误伤 {bad} 次")

    # 3. 敲码中途退格最多的码
    mid = collections.Counter(e["code"] for e in ev if e["e"] == "bs" and e.get("composing") and e.get("code"))
    if mid:
        print("\n== 敲码中途退格最多的码（退格之前的码）：")
        for c, v in mid.most_common(15):
            print(f"  {v:>3}x  {c}")
    cancels = collections.Counter(e["code"] for e in ev if e["e"] == "cancel")
    if cancels:
        print("\n== Esc 取消最多的码：")
        for c, v in cancels.most_common(10):
            print(f"  {v:>3}x  {c}")


if __name__ == "__main__":
    main()
