from lib.public import compute, format_result
r = compute()
assert r == {'ok': True, 'data': 1}
assert format_result(9) == {'ok': True, 'data': 9}
