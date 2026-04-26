import unittest
from types import SimpleNamespace

import run_udp_crypto_control_regression as regression
import udp_crypto_control as ctrl


def make_status_payload(
    *,
    binding_id: int,
    session_id: int,
    authorized_mask: int,
    locked: int,
    rx_ctrl_ok: int = 0,
    rx_data_ok: int = 0,
    tx_ok: int = 0,
    drop_invalid: int = 0,
    drop_unauthorized: int = 0,
    drop_replay: int = 0,
    bind_fail: int = 0,
    lock_events: int = 0,
    crypto_timeout: int = 0,
    crypto_fail: int = 0,
) -> bytes:
    return ctrl.STATUS_STRUCT.pack(
        binding_id,
        session_id,
        authorized_mask,
        locked,
        rx_ctrl_ok,
        rx_data_ok,
        tx_ok,
        drop_invalid,
        drop_unauthorized,
        drop_replay,
        bind_fail,
        lock_events,
        crypto_timeout,
        crypto_fail,
    )


def make_bench_payload(algo: str, repeats: int) -> bytes:
    algo_id = ctrl.ALGO_SM4 if algo == "sm4" else ctrl.ALGO_AES
    payload = bytearray(ctrl.BENCH_HEADER_STRUCT.pack(algo_id, 5, repeats))
    for length, sw_us, hw_us in ((16, 50, 10), (32, 80, 20), (128, 300, 60), (512, 1100, 200), (1472, 3200, 700)):
        payload.extend(ctrl.BENCH_RECORD_STRUCT.pack(length, 0, sw_us, hw_us))
    return bytes(payload)


class FakeClient:
    def __init__(self, session_id: int, timeout: float):
        self.ip = "192.168.1.20"
        self.port = ctrl.CONTROL_PORT
        self.timeout = timeout
        self.binding_id = ctrl.DEFAULT_BINDING_ID
        self.session_id = 0
        self.seq_id = 0
        self._next_session_id = session_id
        self._authorized_mask = 0
        self._locked = 0
        self.closed = False

    def close(self) -> None:
        self.closed = True

    def hello(self):
        self.session_id = self._next_session_id
        self.seq_id = 0
        return SimpleNamespace(session_id=self.session_id)

    def set_key(self, algo: str, user_key=None, dual_enable: bool = False):
        self.seq_id += 1
        self._authorized_mask = ctrl.ALGO_FLAG_AES | ctrl.ALGO_FLAG_SM4 if dual_enable else ctrl.algo_to_flag(algo)
        return SimpleNamespace(status_code=ctrl.STATUS_OK)

    def status(self):
        self.seq_id += 1
        return SimpleNamespace(
            payload=make_status_payload(
                binding_id=self.binding_id,
                session_id=self.session_id,
                authorized_mask=self._authorized_mask,
                locked=self._locked,
            )
        )

    def lock(self):
        self.seq_id += 1
        self._locked = 1
        self._authorized_mask = 0
        return SimpleNamespace(status_code=ctrl.STATUS_OK)

    def unlock(self):
        self.seq_id += 1
        self._locked = 0
        self._authorized_mask = 0
        return SimpleNamespace(status_code=ctrl.STATUS_OK)

    def bench(self, algo: str, repeats: int):
        self.seq_id += 1
        return SimpleNamespace(payload=make_bench_payload(algo, repeats))


class ControlRegressionPlanTests(unittest.TestCase):
    def test_regression_uses_separate_bench_client_and_timeout(self) -> None:
        created = []
        outputs = []

        def client_factory(ip: str, source_ip: str, timeout: float, port: int):
            session_id = 1 if len(created) == 0 else 2
            client = FakeClient(session_id=session_id, timeout=timeout)
            created.append(client)
            return client

        replay_calls = []

        def raw_transact(client, packet):
            replay_calls.append((client.session_id, len(replay_calls)))
            status = ctrl.STATUS_OK if len(replay_calls) == 1 else ctrl.STATUS_REPLAY
            return SimpleNamespace(status_code=status)

        regression.run_regression(
            ip=ctrl.DEFAULT_IP,
            source_ip=ctrl.DEFAULT_SOURCE_IP,
            timeout=3.0,
            bench_timeout=10.0,
            port=ctrl.CONTROL_PORT,
            bench_repeats=8,
            client_factory=client_factory,
            raw_transact=raw_transact,
            emit=outputs.append,
        )

        self.assertEqual([client.timeout for client in created], [3.0, 10.0])
        self.assertTrue(created[0].closed)
        self.assertTrue(created[1].closed)
        self.assertEqual(len(replay_calls), 2)
        self.assertIn("session_id=0x00000001", outputs)
        self.assertIn("bench_session_id=0x00000002", outputs)
        self.assertIn("authorized_mask=0x03", outputs)
        self.assertIn("CASE bench aes", outputs)
        self.assertIn("CASE bench sm4", outputs)

    def test_regression_fails_if_unlock_does_not_rotate_session(self) -> None:
        def client_factory(ip: str, source_ip: str, timeout: float, port: int):
            return FakeClient(session_id=1, timeout=timeout)

        def raw_transact(client, packet):
            if not hasattr(raw_transact, "count"):
                raw_transact.count = 0
            raw_transact.count += 1
            status = ctrl.STATUS_OK if raw_transact.count == 1 else ctrl.STATUS_REPLAY
            return SimpleNamespace(status_code=status)

        with self.assertRaisesRegex(RuntimeError, "session_id did not rotate"):
            regression.run_regression(
                ip=ctrl.DEFAULT_IP,
                source_ip=ctrl.DEFAULT_SOURCE_IP,
                timeout=3.0,
                bench_timeout=10.0,
                port=ctrl.CONTROL_PORT,
                bench_repeats=8,
                client_factory=client_factory,
                raw_transact=raw_transact,
                emit=lambda _line: None,
            )


if __name__ == "__main__":
    unittest.main()
