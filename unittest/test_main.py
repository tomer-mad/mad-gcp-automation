import unittest
import base64
import json
from unittest.mock import Mock

# Import the function you want to test
from main import budget_alert_handler


class TestBudgetAlert(unittest.TestCase):

    def setUp(self):
        # This is the fake context object Cloud Functions expects
        self.mock_context = Mock()
        self.mock_context.event_id = '123456789'
        self.mock_context.timestamp = '2023-10-01T00:00:00Z'

    def test_budget_logic_success(self):
        """Test that the function correctly decodes a valid payload."""

        # 1. Define the plain JSON (What you actually want to test)
        plain_payload = {
            "budgetDisplayName": "test-budget-dev
                        }