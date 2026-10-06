---
'openzeppelin-confidential-contracts': minor
---

`Auditor`: Add an abstract contract with internal `_addAuditor` and `_removeAuditor` functions that grant and revoke wildcard user decryption delegation, allowing an auditor to decrypt all handles the inheriting contract can decrypt (without being able to operate on them).
