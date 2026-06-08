STATUS = 'open'

def invariant_ok():
    return STATUS == 'fixed' and _checksum() == 42

def _checksum():
    return 41
