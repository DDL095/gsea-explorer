"""
audit_logger.py — Dual-format audit log (gsealens-explorer v0.2.1)
Writes both audit.log (text) and audit.jsonl (JSON Lines).

Usage:
    from audit_logger import AuditLogger
    log = AuditLogger("/path/to/out_dir")
    log.start()
    log.event("S0", "rds_found", path="...", size_bytes=123)
    log.end()
"""

import json
import os
from datetime import datetime
from typing import Any, Optional


class AuditLogger:
    def __init__(self, out_dir: str, agent_name: str = "gsealens-explorer", version: str = "0.2.1"):
        self.out_dir = out_dir
        self.agent_name = agent_name
        self.version = version
        self.log_path = os.path.join(out_dir, "audit.log")
        self.jsonl_path = os.path.join(out_dir, "audit.jsonl")
        self.start_time: Optional[datetime] = None
        os.makedirs(out_dir, exist_ok=True)
        for p in (self.log_path, self.jsonl_path):
            if os.path.exists(p):
                os.remove(p)

    def _now(self) -> str:
        return datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]

    def _now_iso(self) -> str:
        return datetime.now().isoformat(timespec="seconds")

    def _write_text(self, level: str, msg: str) -> None:
        with open(self.log_path, "a", encoding="utf-8") as f:
            f.write(f"[{self._now()}] [{level:6}] {msg}\n")

    def _write_jsonl(self, level: str, event: str, **kwargs) -> None:
        record = {"ts": self._now_iso(), "level": level, "event": event,
                  "agent": self.agent_name, "version": self.version}
        record.update(kwargs)
        with open(self.jsonl_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")

    def start(self, **kwargs) -> None:
        self.start_time = datetime.now()
        self._write_text("SYSTEM", f"{self.agent_name} v{self.version} started")
        self._write_jsonl("SYSTEM", "start", **kwargs)

    def end(self, **kwargs) -> None:
        if self.start_time:
            duration = (datetime.now() - self.start_time).total_seconds()
            self._write_text("SYSTEM", f"{self.agent_name} v{self.version} finished ({duration:.2f}s)")
            self._write_jsonl("SYSTEM", "end", duration_s=duration, **kwargs)
        else:
            self._write_text("SYSTEM", f"{self.agent_name} finished")
            self._write_jsonl("SYSTEM", "end", **kwargs)

    def event(self, level: str, event: str, **kwargs) -> None:
        kwargs_str = " ".join(f"{k}={v}" for k, v in kwargs.items())
        self._write_text(level, f"{event}  {kwargs_str}")
        self._write_jsonl(level, event, **kwargs)

    # Convenience methods
    def s0_rds_found(self, path, size_bytes, platform_hint=""):
        self.event("S0", "rds_found", path=path, size_bytes=size_bytes, platform_hint=platform_hint)

    def s0_platform_detected(self, platform, class_chain, profile=""):
        self.event("S0", "platform_detected", platform=platform,
                   class_chain=list(class_chain), profile=profile)

    def s1_ask(self, q_id, q_text, q_type="free-form"):
        self.event("S1", "ask", q_id=q_id, q_text=q_text, type=q_type)

    def s1_answer(self, q_id, answer_text):
        self.event("S1", "answer", q_id=q_id, answer_text=answer_text)

    def state_transition(self, from_phase, to_phase, trigger):
        self.event("STATE", "transition", **{"from": from_phase, "to": to_phase, "trigger": trigger})

    def data_extracted(self, files, rows_total, bytes_total):
        self.event("S4", "data_extracted", files=files, rows_total=rows_total, bytes_total=bytes_total)

    def skill_call(self, skill, **inputs):
        self.event("S5", "skill_call", skill=skill, **inputs)

    def skill_result(self, skill, status, duration_s, output_summary=""):
        self.event("S5", "skill_result", skill=skill, status=status,
                   duration_s=duration_s, output_summary=output_summary)

    def skill_fail(self, skill, attempt, max_attempts, reason):
        self.event("S5", "skill_fail", skill=skill, attempt=attempt,
                   max_attempts=max_attempts, reason=reason)

    def gate(self, gate_id, name, result, details=""):
        self.event("S7", "gate", gate_id=gate_id, name=name, result=result, details=details)

    def report_written(self, path, lines):
        self.event("S8", "report_written", path=path, lines=lines)

    def abort(self, reason):
        self.event("SYSTEM", "abort", reason=reason)


if __name__ == "__main__":
    # Smoke test
    log = AuditLogger("/tmp/gsea_test_audit")
    log.start()
    log.s0_rds_found("/tmp/test.rds", 1024, "gsealens")
    log.s0_platform_detected("gsealens", ["GseaRes", "list"])
    log.s1_ask("Q1", "造模/处理方式是什么?")
    log.s1_answer("Q1", "成年小鼠腹腔注射 caerulein 50 ug/kg x 7")
    log.state_transition("S1", "S2", "5/5 answered")
    log.skill_call("reactome-skill", pathway="R-HSA-109582")
    log.skill_result("reactome-skill", "success", 1.2, "12 upstream")
    log.gate("G1", "数据支撑", "PASS", "5/5")
    log.report_written("01_exploratory_analysis_report.md", 140)
    log.end()
    print(f"OK: {log.log_path}")
    print(f"OK: {log.jsonl_path}")
    with open(log.log_path, encoding="utf-8") as f:
        print(f.read())
