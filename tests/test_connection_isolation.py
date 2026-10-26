"""Regression: pooled SERIALIZABLE sessions caused payment/cancel lock timeouts."""
import pytest
from app.db import query
from tests.test_integration import test_payment_cancel_race_preserves_final_state as payment_cancel_scenario

def test_new_connection_restores_default_isolation(sql_ready):
    for _ in range(5):
        query('SET TRANSACTION ISOLATION LEVEL SERIALIZABLE; SELECT 1 Probe')
        row=query('SELECT transaction_isolation_level IsolationLevel FROM sys.dm_exec_sessions WHERE session_id=@@SPID',one=True)
        assert row['IsolationLevel']==2  # READ COMMITTED, not SERIALIZABLE (4)

@pytest.mark.parametrize('attempt',range(3))
def test_payment_cancel_after_serializable_work(app,users,flight,attempt):
    query('SET TRANSACTION ISOLATION LEVEL SERIALIZABLE; SELECT 1 Probe')
    payment_cancel_scenario(app,users,flight)
