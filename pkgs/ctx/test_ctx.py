import io
import sqlite3
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import ctx


def _varint_bytes(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def _pb_field(num, value):
    if isinstance(value, int):
        return _varint_bytes(num << 3) + _varint_bytes(value)
    return _varint_bytes((num << 3) | 2) + _varint_bytes(len(value)) + value


class CtxTest(unittest.TestCase):
    def test_protobuf_varint_fields_and_nested_pb(self):
        nested = _pb_field(1, 1700000000) + _pb_field(2, 500_000_000)
        msg = _pb_field(1, 14) + _pb_field(5, _pb_field(1, nested)) + bytes([(3 << 3) | 5]) + b"\x01\x02\x03\x04"

        parsed = ctx.fields(msg)
        self.assertEqual(parsed[0], (1, 14))
        self.assertEqual(parsed[2], (3, b"\x01\x02\x03\x04"))
        self.assertEqual(ctx.pb(msg, 1), 14)
        self.assertEqual(ctx.pb(msg, 5, 1, 1), 1700000000)
        self.assertEqual(ctx.pb(msg, 5, 1, 2), 500_000_000)
        self.assertIsNone(ctx.pb(msg, 99, default=None))

        with self.assertRaises(ValueError):
            ctx.fields(bytes([(1 << 3) | 7]))

    def test_chunk_soft_hard_cuts_and_provisional_tail(self):
        events = [
            (10, "2026-01-01T00:00:00Z", "A" * ctx.SOFT),
            (20, "2026-01-01T00:01:00Z", "## USER 2026-01-01 00:01\nhi"),
            (30, "2026-01-01T00:02:00Z", "B" * (ctx.HARD + 1)),
            (40, "2026-01-01T00:03:00Z", "short tail"),
        ]
        chunks_open, reached_open = ctx.chunk(events, 0, ended=False)
        self.assertEqual(len(chunks_open), 3)
        self.assertEqual(chunks_open[0]["off"], [0, 10])
        self.assertEqual(chunks_open[1]["off"], [10, 20])
        self.assertEqual(chunks_open[2]["off"], [20, 30])
        self.assertEqual(reached_open, 30)

        chunks_ended, reached_ended = ctx.chunk(events, 0, ended=True)
        self.assertEqual(len(chunks_ended), 4)
        self.assertEqual(chunks_ended[3]["off"], [30, 40])
        self.assertEqual(reached_ended, 40)

    def test_tree_refs_cover_and_budget_view(self):
        self.assertEqual(ctx.span(2, 1), (4, 4))
        self.assertEqual(ctx.parse_ref("4+4"), (2, 1))
        with self.assertRaises(SystemExit):
            ctx.parse_ref("2+4")
        with self.assertRaises(SystemExit):
            ctx.parse_ref("0+3")

        with tempfile.TemporaryDirectory() as tmp:
            p = ctx.Project("demo")
            p.dir = Path(tmp)
            p.chunks = [
                {"i": i, "t0": f"2026-01-0{i+1}T00:00:00Z", "t1": f"2026-01-0{i+1}T01:00:00Z",
                 "role": "builder", "session": f"sess-{i}", "text": "x" * 200}
                for i in range(4)
            ]
            p.nodes = {
                (0, 0): "l0", (0, 1): "l1", (0, 2): "l2", (0, 3): "l3",
                (1, 0): "m0", (1, 1): "m1",
                (2, 0): "root",
            }
            self.assertEqual(ctx.roots(4), [(2, 0)])
            self.assertEqual(ctx.cover(p, 2, 0), [(2, 0)])

            two_branches = ctx.view(p, budget=1000)
            self.assertEqual(two_branches, [(0, 0), (0, 1), (0, 2), (0, 3)])

            # Tight budget expands the newer right subtree before the older left one.
            tight_budget = sum(len(ctx.line(p, *n)) + 1 for n in [(1, 0), (0, 2), (0, 3)])
            self.assertEqual(ctx.view(p, budget=tight_budget), [(1, 0), (0, 2), (0, 3)])

    def test_extract_json_object_and_parse_dir_map(self):
        reply = 'Here is {not json} and then {"0": "summary text", "1": "more"} tail {ignored'
        self.assertEqual(ctx.extract_json_object(reply), {"0": "summary text", "1": "more"})
        with self.assertRaises(ValueError):
            ctx.extract_json_object("no braces here")

        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / "agy-dirs"
            cfg.write_text("# comment\n\n/home/u/with spaces/proj* advisor\nbadline\n/opt/repo builder\n")
            self.assertEqual(
                ctx.parse_dir_map(cfg),
                [["/home/u/with spaces/proj*", "advisor"], ["/opt/repo", "builder"]],
            )

    def test_cmd_hook_ignores_empty_malformed_and_missing_path(self):
        for payload in ("", "   ", "{bad json", "[]", "{}", '{"transcript_path": ""}'):
            with patch("sys.stdin", io.StringIO(payload)), patch("subprocess.Popen") as popen:
                ctx.cmd_hook(None, SimpleNamespace())
                popen.assert_not_called()

    def test_agy_events_missing_timestamp_and_pending_status(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = Path(tmp) / "conv.db"
            con = sqlite3.connect(db)
            con.execute("CREATE TABLE steps (idx INTEGER, status INTEGER, step_payload BLOB)")
            prompt_no_ts = _pb_field(1, 14) + _pb_field(19, _pb_field(2, b"hello"))
            ts_nested = _pb_field(5, _pb_field(1, _pb_field(1, 1_700_000_000)))
            reply_with_ts = _pb_field(1, 15) + ts_nested + _pb_field(20, _pb_field(1, b"world"))
            pending = _pb_field(1, 15) + ts_nested + _pb_field(20, _pb_field(1, b"unsettled"))
            con.executemany(
                "INSERT INTO steps VALUES (?, ?, ?)",
                [(0, 3, prompt_no_ts), (1, 3, reply_with_ts), (2, 1, pending)],
            )
            con.commit()
            con.close()

            events = list(ctx.agy_events(str(db), 0))
            self.assertEqual(len(events), 2)
            self.assertIsNone(events[0][1])
            self.assertTrue(events[0][2].startswith("## PROMPT ?\nhello"))
            self.assertEqual(events[1][1], ctx.iso(1_700_000_000_000))
            self.assertIn("world", events[1][2])
