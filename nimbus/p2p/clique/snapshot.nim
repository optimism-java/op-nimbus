# Nimbus
# Copyright (c) 2018 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or
#    http://www.apache.org/licenses/LICENSE-2.0)
#  * MIT license ([LICENSE-MIT](LICENSE-MIT) or
#    http://opensource.org/licenses/MIT)
# at your option. This file may not be copied, modified, or distributed except
# according to those terms.

##
## Snapshot Structure for Clique PoA Consensus Protocol
## ====================================================
##
## For details see
## `EIP-225 <https://github.com/ethereum/EIPs/blob/master/EIPS/eip-225.md>`_
## and
## `go-ethereum <https://github.com/ethereum/EIPs/blob/master/EIPS/eip-225.md>`_
##

const
   # debugging, enable with: nim c -r -d:noisy:3 ...
   noisy {.intdefine.}: int = 0
   isMainOk {.used.} = noisy > 2

import
  ../../db/[storage_types, db_chain],
  ../../utils/lru_cache,
  ./clique_cfg,
  ./clique_defs,
  ./clique_poll,
  ./ec_recover,
  algorithm,
  chronicles,
  eth/[common, rlp, trie/db],
  sequtils,
  strformat,
  strutils,
  tables,
  times

type
  AddressHistory = Table[BlockNumber,EthAddress]

  SnapshotData* = object
    blockNumber: BlockNumber ## truncated block num where snapshot was created
    blockHash: Hash256       ## block hash where snapshot was created
    recents: AddressHistory  ## recent signers for spam protections

    # clique/snapshot.go(58): Recents map[uint64]common.Address [..]
    ballot: CliquePoll       ## Votes => authorised signers

  # clique/snapshot.go(50): type Snapshot struct [..]
  Snapshot* = object ## Snapshot is the state of the authorization voting at
                     ## a given point in time.
    cfg: CliqueCfg           ## parameters to fine tune behavior
    data*: SnapshotData      ## real snapshot

{.push raises: [Defect,CatchableError].}

logScope:
  topics = "clique PoA snapshot"

# ------------------------------------------------------------------------------
# Pretty printers for debugging
# ------------------------------------------------------------------------------

proc getPrettyPrinters(s: var Snapshot): var PrettyPrinters =
  ## Mixin for pretty printers
  s.cfg.prettyPrint

proc pp(s: var Snapshot; h: var AddressHistory): string =
  toSeq(h.keys)
    .mapIt(it.truncate(uint64))
    .sorted
    .mapIt("#" & $it & ":" & s.pp(h[it.u256]))
    .join(",")

proc pp(s: var Snapshot; v: Vote): string =
  proc authorized(b: bool): string =
    if b: ",auhorized" else: ""
  "{" & &"signer={s.pp(v.signer)}" &
        &",address={s.pp(v.address)}" &
        &",blockNumber={v.blockNumber.truncate(uint64)}" &
        &"{authorized(v.authorize)}" & "}"

proc pp(s: var Snapshot;
        v: (EthAddress,EthAddress,Vote); delim: string): string =
  &"(account={s.pp(v[0])}" &
    &"{delim}signer={s.pp(v[1])}" &
    &"{delim}vote={s.pp(v[2])})"

proc pp(s: var Snapshot;
        w: seq[(EthAddress,EthAddress,Vote)]; sep1, sep2: string): string =
  w.mapIt(s.pp(it,sep1)).join(sep2)

proc pp(s: var Snapshot;
        w: seq[(EthAddress,EthAddress,Vote)]; indent = 0): string =
  let
    sep1 = if 0 < indent: "\n" & ' '.repeat(indent) else: ","
    sep2 = if 0 < indent: "\n" & ' '.repeat(indent) else: " "
  s.pp(w,sep1,sep2)

# ------------------------------------------------------------------------------
# Public pretty printers
# ------------------------------------------------------------------------------

proc pp*(s: var Snapshot; delim: string): string =
  ## Pretty print descriptor
  let
    sep1 = if 0 < delim.len: delim
           else: ";"
    sep2 = if 0 < delim.len and delim[0] == '\n': delim & ' '.repeat(8)
           else: ";"
    sep3 = if 0 < delim.len and delim[0] == '\n': delim & ' '.repeat(7)
           else: ";"
  &"(blockNumber=#{s.data.blockNumber}" &
    &"{sep1}recents=[{s.pp(s.data.recents)}]" &
    &"{sep1}votes=[" &
      s.pp(s.data.ballot.votesInternal,sep2,sep3) &
      "])"

proc pp*(s: var Snapshot; indent = 0): string =
  ## Pretty print descriptor
  let delim = if 0 < indent: "\n" & ' '.repeat(indent) else: " "
  s.pp(delim)

# ------------------------------------------------------------------------------
# Private functions needed to support RLP conversion
# ------------------------------------------------------------------------------

proc append[K,V](rw: var RlpWriter; tab: Table[K,V]) {.inline.} =
  rw.startList(tab.len)
  for key,value in tab.pairs:
    rw.append((key,value))

proc read[K,V](rlp: var Rlp;
        Q: type Table[K,V]): Q {.inline, raises: [Defect,CatchableError].} =
  for w in rlp.items:
    let (key,value) = w.read((K,V))
    result[key] = value

# ------------------------------------------------------------------------------
# Public functions
# ------------------------------------------------------------------------------

# clique/snapshot.go(72): func newSnapshot(config [..]
proc initSnapshot*(s: var Snapshot; cfg: CliqueCfg;
           number: BlockNumber; hash: Hash256; signers: openArray[EthAddress]) =
  ## This creates a new snapshot with the specified startup parameters. The
  ## method does not initialize the set of recent signers, so only ever use
  ## if for the genesis block.
  s.cfg = cfg
  s.data.blockNumber = number
  s.data.blockHash = hash
  s.data.recents = initTable[BlockNumber,EthAddress]()
  s.data.ballot.initCliquePoll(signers)
  echo ">>> initSnapshot #", number.truncate(uint64),
    " >> ", s.pp(s.data.ballot.authSigners)

proc initSnapshot*(cfg: CliqueCfg; number: BlockNumber; hash: Hash256;
                   signers: openArray[EthAddress]): Snapshot =
  result.initSnapshot(cfg, number, hash, signers)


proc blockNumber*(s: var Snapshot): BlockNumber =
  ## Getter
  s.data.blockNumber

# clique/snapshot.go(88): func loadSnapshot(config [..]
proc loadSnapshot*(s: var Snapshot; cfg: CliqueCfg;
           hash: Hash256): CliqueResult {.gcsafe, raises: [Defect].} =
  ## Load an existing snapshot from the database.
  try:
    let
      key = hash.cliqueSnapshotKey
      value = cfg.dbChain.db.get(key.toOpenArray)
    s.data = value.decode(SnapshotData)
    s.cfg = cfg
  except CatchableError as e:
    return err((errSnapshotLoad,e.msg))
  result = ok()


# clique/snapshot.go(104): func (s *Snapshot) store(db [..]
proc storeSnapshot*(s: var Snapshot): CliqueResult {.gcsafe,raises: [Defect].} =
  ## Insert the snapshot into the database.
  try:
    let
      key = s.data.blockHash.cliqueSnapshotKey
      value = rlp.encode(s.data)
    s.cfg.dbChain.db.put(key.toOpenArray, value)
  except CatchableError as e:
    return err((errSnapshotStore,e.msg))
  result = ok()


# clique/snapshot.go(185): func (s *Snapshot) apply(headers [..]
proc applySnapshot*(s: var Snapshot;
                    headers: openArray[BlockHeader]): CliqueResult =
  ## Initialises an authorization snapshot `snap` by applying the `headers`
  ## to the argument snapshot `s`.

  echo ">>> applySnapshot ", s.pp(headers).join("\n" & ' '.repeat(18))

  # Allow passing in no headers for cleaner code
  if headers.len == 0:
    return ok()

  # Sanity check that the headers can be applied
  if headers[0].blockNumber != s.data.blockNumber + 1:
    return err((errInvalidVotingChain,""))
  # clique/snapshot.go(191): for i := 0; i < len(headers)-1; i++ {
  for i in 0 ..< headers.len - 1:
    if headers[i+1].blockNumber != headers[i].blockNumber+1:
      return err((errInvalidVotingChain,""))

  # Iterate through the headers and create a new snapshot
  let
    start = getTime()
    logInterval = initDuration(seconds = 8)
  var
    logged = start

  # clique/snapshot.go(206): for i, header := range headers [..]
  for headersIndex in 0 ..< headers.len:
    echo ">>> applySnapshot headersIndex=", headersIndex
    let
      # headersIndex => also used for logging at the end of this loop
      header = headers[headersIndex]
      number = header.blockNumber

    echo "<<< applySnapshot 1"

    # Remove any votes on checkpoint blocks
    if (number mod s.cfg.epoch) == 0:
      s.data.ballot.initCliquePoll

    # Delete the oldest signer from the recent list to allow it signing again
    block:
      let limit = s.data.ballot.authSignersThreshold.u256
      if limit <= number:
        s.data.recents.del(number - limit)

    echo "<<< applySnapshot 2 snap=", s.pp(26)

    # Resolve the authorization key and check against signers
    let signer = ? s.cfg.signatures.getEcRecover(header)
    echo "<<< applySnapshot 3 ", s.pp(signer)

    if not s.data.ballot.isAuthSigner(signer):
      echo "<<< applySnapshot 3 => fail ", s.pp(29)
      return err((errUnauthorizedSigner,""))

    echo "<<< applySnapshot 4"
    for recent in s.data.recents.values:
      if recent == signer:
        return err((errRecentlySigned,""))
    s.data.recents[number] = signer

    echo "<<< applySnapshot 5"

    # Header authorized, discard any previous vote from the signer
    # clique/snapshot.go(233): for i, vote := range snap.Votes {
    s.data.ballot.delVote(signer = signer, address = header.coinbase)

    # Tally up the new vote from the signer
    # clique/snapshot.go(244): var authorize bool
    var authOk = false
    if header.nonce == NONCE_AUTH:
      authOk = true
    elif header.nonce != NONCE_DROP:
      return err((errInvalidVote,""))
    let vote = Vote(address:     header.coinbase,
                    signer:      signer,
                    blockNumber: number,
                    authorize:   authOk)
    echo "<<< applySnapshot calling addVote ", s.pp(vote)
    # clique/snapshot.go(253): if snap.cast(header.Coinbase, authorize) {
    s.data.ballot.addVote(vote)

    echo "<<< applySnapshot 6 ", s.pp(21)

    # clique/snapshot.go(269): if limit := uint64(len(snap.Signers)/2 [..]
    if s.data.ballot.authSignersShrunk:
      # Signer list shrunk, delete any leftover recent caches
      let limit = s.data.ballot.authSignersThreshold.u256
      if limit <= number:
        s.data.recents.del(number - limit)

    echo "<<< applySnapshot 7"

    # If we're taking too much time (ecrecover), notify the user once a while
    if logInterval < logged - getTime():
      info "Reconstructing voting history",
        processed = headersIndex,
        total = headers.len,
        elapsed = start - getTime()
      logged = getTime()

  let sinceStart = start - getTime()
  if logInterval < sinceStart:
    info "Reconstructed voting history",
      processed = headers.len,
      elapsed = sinceStart

  # clique/snapshot.go(303): snap.Number += uint64(len(headers))
  s.data.blockNumber += headers.len.u256
  s.data.blockHash = headers[^1].blockHash
  result = ok()

proc validVote*(s: var Snapshot; address: EthAddress; authorize: bool): bool =
  ## Returns `true` if voting makes sense, at all.
  s.data.ballot.validVote(address, authorize)

proc recent*(s: var Snapshot; address: EthAddress): Result[BlockNumber,void] =
  ## Return `BlockNumber` for `address` argument (if any)
  for (number,recent) in s.data.recents.pairs:
    if recent == address:
      return ok(number)
  return err()

proc signersThreshold*(s: var Snapshot): int =
  ## Forward to `CliquePoll`: Minimum number of authorised signers needed.
  s.data.ballot.authSignersThreshold

proc isSigner*(s: var Snapshot; address: EthAddress): bool =
  ## Checks whether argukment ``address` is in signers list
  s.data.ballot.isAuthSigner(address)

proc signers*(s: var Snapshot): seq[EthAddress] =
  ## Retrieves the sorted list of authorized signers
  s.data.ballot.authSigners


# clique/snapshot.go(319): func (s *Snapshot) inturn(number [..]
proc inTurn*(s: var Snapshot; number: BlockNumber, signer: EthAddress): bool =
  ## Returns `true` if a signer at a given block height is in-turn or not.
  let ascSignersList = s.data.ballot.authSigners
  for offset in 0 ..< ascSignersList.len:
    if ascSignersList[offset] == signer:
      return (number mod ascSignersList.len.u256) == offset.u256

# ------------------------------------------------------------------------------
# End
# ------------------------------------------------------------------------------