import os
import sys
import unittest


def main() -> int:
    test_dir = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, test_dir)
    suite = unittest.defaultTestLoader.discover(test_dir, pattern="test_*.py")
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main())
