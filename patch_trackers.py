with open("docs/tracker/BLOCKERS.md", "r") as f:
    c = f.read()

c = c.replace("## 2. Hardware / Owner verification required\n\n- S7.7 `Capture/` camera bounds scaling and alignment (needs physical iPhone).", "## 2. Hardware / Owner verification required\n\n- S7.7 `Capture/` camera bounds scaling and alignment (needs physical iPhone).\n- S7.8 Hardware pass (needs physical iPhone to test real-world camera alignment and route rechecks).")

with open("docs/tracker/BLOCKERS.md", "w") as f:
    f.write(c)

with open("docs/tracker/TODO.md", "r") as f:
    c = f.read()

c = c.replace("- [ ] **S7.8** Exit path recheck (scan a corridor, diff objects)", "- [x] **S7.8** Exit path recheck (scan a corridor, diff objects) (hardware deferred)")

with open("docs/tracker/TODO.md", "w") as f:
    f.write(c)

