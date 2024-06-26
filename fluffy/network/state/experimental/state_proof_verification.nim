# Nimbus
# Copyright (c) 2023-2024 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at https://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at https://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.push raises: [].}

import
  std/sequtils,
  stint,
  eth/[common, rlp, trie/hexary_proof_verification],
  stew/results,
  ./state_proof_types

export results

proc verifyAccount*(
    trustedStateRoot: KeccakHash,
    address: EthAddress,
    account: Account,
    proof: AccountProof,
): Result[void, string] =
  if proof.len() == 0:
    return err("proof is empty")

  let key = toSeq(keccakHash(address).data)
  let value = rlp.encode(account)

  let proofResult = verifyMptProof(proof.MptProof, trustedStateRoot, key, value)

  case proofResult.kind
  of ValidProof:
    ok()
  of MissingKey:
    err("missing key")
  of InvalidProof:
    err(proofResult.errorMsg)

proc verifyContractStorageSlot*(
    trustedStorageRoot: KeccakHash,
    slotKey: UInt256,
    slotValue: UInt256,
    proof: StorageProof,
): Result[void, string] =
  if proof.len() == 0:
    return err("proof is empty")

  let key = toSeq(keccakHash(toBytesBE(slotKey)).data)
  let value = rlp.encode(slotValue)

  let proofResult = verifyMptProof(proof.MptProof, trustedStorageRoot, key, value)

  case proofResult.kind
  of ValidProof:
    ok()
  of MissingKey:
    err("missing key")
  of InvalidProof:
    err(proofResult.errorMsg)

func verifyContractBytecode*(
    trustedCodeHash: KeccakHash, bytecode: openArray[byte]
): Result[void, string] =
  if trustedCodeHash == keccakHash(bytecode):
    ok()
  else:
    err("hash of bytecode doesn't match the expected code hash")
