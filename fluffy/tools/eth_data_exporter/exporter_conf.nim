# Nimbus
# Copyright (c) 2023-2024 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at https://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at https://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.push raises: [].}

import std/[os, uri], confutils, chronicles, beacon_chain/spec/digest

proc defaultDataDir*(): string =
  let dataDir =
    when defined(windows):
      "AppData" / "Roaming" / "EthData"
    elif defined(macosx):
      "Library" / "Application Support" / "EthData"
    else:
      ".cache" / "eth-data"

  getHomeDir() / dataDir

type
  Web3UrlKind* = enum
    HttpUrl
    WsUrl

  Web3Url* = object
    kind*: Web3UrlKind
    url*: string

  StorageMode* = enum
    JsonStorage
    DbStorage

const
  defaultDataDirDesc* = defaultDataDir()
  defaultBlockFileName* = "eth-block-data"
  defaultAccumulatorFileName* = "mainnet-master-accumulator.ssz"
  defaultWeb3Url* = Web3Url(kind: HttpUrl, url: "http://127.0.0.1:8545")

type
  ExporterCmd* = enum
    history
    beacon

  HistoryCmd* = enum
    # TODO: Multiline strings doesn't work here anymore with 1.6, and concat of
    # several lines gives the error: Error: Invalid node kind nnkInfix for macros.`$`
    exportBlockData =
      "Export block data (headers, bodies and receipts) to a json format or a database. Some of this functionality is likely to get deprecated"
    exportEpochHeaders =
      "Export block headers from an Ethereum JSON RPC Execution endpoint to *.e2s files arranged per epoch (8192 blocks)"
    verifyEpochHeaders =
      "Verify *.e2s files containing block headers. Verify currently only means being able to RLP decode the block headers"
    exportAccumulatorData =
      "Build and export the master accumulator and historical epoch accumulators. Requires *.e2s block header files generated with the exportHeaders command up until the merge block"
    printAccumulatorData =
      "Print the root hash of the master accumulator and of all historical epoch accumulators. Requires data generated by exportAccumulatorData command"
    exportHeaderRange =
      "Export block headers from an Ethereum JSON RPC Execution endpoint to *.e2s files (unlimited amount)"
    exportHeadersWithProof =
      "Export block headers with proof from *.e2s headers file and epochAccumulator files"
    exportEra1 = "Export historical data to era1 store"
    verifyEra1 = "Read and verify historical data from era1 store"

  BeaconCmd* = enum
    exportLCBootstrap = "Export Light Client Bootstrap"
    exportLCUpdates = "Export Light Client Updates"
    exportLCFinalityUpdate = "Export Light Client Finality Update"
    exportLCOptimisticUpdate = "Export Light Client Optimistic Update"

  ExporterConf* = object
    logLevel* {.
      defaultValue: LogLevel.INFO,
      defaultValueDesc: $LogLevel.INFO,
      desc: "Sets the log level",
      name: "log-level"
    .}: LogLevel
    dataDir* {.
      desc: "The directory where generated data files will be exported to",
      defaultValue: defaultDataDir(),
      defaultValueDesc: $defaultDataDirDesc,
      name: "data-dir"
    .}: OutDir
    case cmd* {.command.}: ExporterCmd
    of ExporterCmd.history:
      web3Url* {.
        desc: "Execution layer JSON-RPC API URL",
        defaultValue: defaultWeb3Url,
        name: "web3-url"
      .}: Web3Url
      case historyCmd* {.command.}: HistoryCmd
      of exportBlockData:
        startBlock* {.
          desc: "Number of the first block to be exported",
          defaultValue: 0,
          name: "start-block"
        .}: uint64
        endBlock* {.
          desc: "Number of the last block to be exported",
          defaultValue: 0,
          name: "end-block"
        .}: uint64
        fileName* {.
          desc: "File name (minus extension) where block data will be exported to",
          defaultValue: defaultBlockFileName,
          defaultValueDesc: $defaultBlockFileName,
          name: "file-name"
        .}: string
        storageMode* {.
          desc: "Storage mode of block data export",
          defaultValue: JsonStorage,
          name: "storage-mode"
        .}: StorageMode
        headersOnly* {.
          desc: "Only export the headers instead of full blocks and receipts",
          defaultValue: false,
          name: "headers-only"
        .}: bool
      of exportEpochHeaders:
        startEpoch* {.
          desc: "Number of the first epoch which should be downloaded",
          defaultValue: 0,
          name: "start-epoch"
        .}: uint64
        endEpoch* {.
          desc: "Number of the last epoch which should be downloaded",
          defaultValue: 1896,
          name: "end-epoch"
        .}: uint64
      # TODO:
      # Although options are the same as for exportHeaders, we can't drop them
      # under the same case of as confutils does not agree with that.
      of verifyEpochHeaders:
        startEpochVerify* {.
          desc: "Number of the first epoch which should be downloaded",
          defaultValue: 0,
          name: "start-epoch"
        .}: uint64
        endEpochVerify* {.
          desc: "Number of the last epoch which should be downloaded",
          defaultValue: 1896,
          name: "end-epoch"
        .}: uint64
      of exportAccumulatorData:
        accumulatorFileName* {.
          desc: "File to which the serialized accumulator is written",
          defaultValue: defaultAccumulatorFileName,
          defaultValueDesc: $defaultAccumulatorFileName,
          name: "accumulator-file-name"
        .}: string
        writeEpochAccumulators* {.
          desc: "Write also the SSZ encoded epoch accumulators to specific files",
          defaultValue: false,
          name: "write-epoch-accumulators"
        .}: bool
      of printAccumulatorData:
        accumulatorFileNamePrint* {.
          desc: "File from which the serialized accumulator is read",
          defaultValue: defaultAccumulatorFileName,
          defaultValueDesc: $defaultAccumulatorFileName,
          name: "accumulator-file-name"
        .}: string
      of exportHeaderRange:
        startBlockNumber* {.
          desc: "Number of the first block header to be exported", name: "start-block"
        .}: uint64
        endBlockNumber* {.
          desc: "Number of the last block header to be exported", name: "end-block"
        .}: uint64
      of exportHeadersWithProof:
        startBlockNumber2* {.
          desc: "Number of the first block header to be exported", name: "start-block"
        .}: uint64
        endBlockNumber2* {.
          desc: "Number of the last block header to be exported", name: "end-block"
        .}: uint64
      of exportEra1:
        era* {.defaultValue: 0, desc: "The era number to write".}: uint64
        eraCount* {.
          defaultValue: 0, name: "count", desc: "Number of eras to write (0=all)"
        .}: uint64
      of verifyEra1:
        era1FileName* {.desc: "Era1 file to read and verify", name: "era1-file-name".}:
          string
    of ExporterCmd.beacon:
      restUrl* {.
        desc: "URL of the beacon node REST service",
        defaultValue: "http://127.0.0.1:5052",
        name: "rest-url"
      .}: string
      case beaconCmd* {.command.}: BeaconCmd
      of exportLCBootstrap:
        trustedBlockRoot* {.
          desc: "Trusted finalized block root of the requested bootstrap",
          name: "trusted-block-root"
        .}: Eth2Digest
      of exportLCUpdates:
        startPeriod* {.
          desc: "Period of the first LC update", defaultValue: 0, name: "start-period"
        .}: uint64
        count* {.
          desc: "Amount of LC updates to request", defaultValue: 1, name: "count"
        .}: uint64
      of exportLCFinalityUpdate:
        discard
      of exportLCOptimisticUpdate:
        discard

proc parseCmdArg*(T: type Web3Url, p: string): T {.raises: [ValueError].} =
  let
    url = parseUri(p)
    normalizedScheme = url.scheme.toLowerAscii()

  if (normalizedScheme == "http" or normalizedScheme == "https"):
    Web3Url(kind: HttpUrl, url: p)
  elif (normalizedScheme == "ws" or normalizedScheme == "wss"):
    Web3Url(kind: WsUrl, url: p)
  else:
    raise newException(
      ValueError,
      "The Web3 URL must specify one of following protocols: http/https/ws/wss",
    )

proc completeCmdArg*(T: type Web3Url, val: string): seq[string] =
  return @[]

proc parseCmdArg*(T: type StorageMode, p: string): T {.raises: [ValueError].} =
  if p == "db":
    return DbStorage
  elif p == "json":
    return JsonStorage
  else:
    let msg = "Provided mode: " & p & " is not a valid. Should be `json` or `db`"
    raise newException(ValueError, msg)

proc completeCmdArg*(T: type StorageMode, val: string): seq[string] =
  return @[]

func parseCmdArg*(
    T: type Eth2Digest, input: string
): T {.raises: [ValueError, Defect].} =
  Eth2Digest.fromHex(input)

func completeCmdArg*(T: type Eth2Digest, input: string): seq[string] =
  return @[]
