# nimbus-eth1
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or
#    http://www.apache.org/licenses/LICENSE-2.0)
#  * MIT license ([LICENSE-MIT](LICENSE-MIT) or
#    http://opensource.org/licenses/MIT)
# at your option. This file may not be copied, modified, or distributed
# except according to those terms.

## Non persistent constructors for Aristo DB
## =========================================
##
{.push raises: [].}

import
  results,
  ../aristo_desc,
  ../aristo_desc/aristo_types_backend,
  "."/[aristo_init_common, aristo_memory]

export
  AristoBackendType, TypedBackendRef

# ------------------------------------------------------------------------------
# Public database constuctors, destructor
# ------------------------------------------------------------------------------

proc newAristoDbRef*(
    backend: static[AristoBackendType];
      ): AristoDbRef =
  ## Simplified prototype for  `BackendNone` and `BackendMemory`  type backend.
  when backend == BackendNone:
    AristoDbRef(top: AristoLayerRef())

  elif backend == BackendMemory:
    AristoDbRef(top: AristoLayerRef(), backend: memoryBackend())

  elif backend == BackendRocksDB:
    {.error: "Aristo DB backend \"BackendRocksDB\" needs basePath argument".}

  else:
    {.error: "Unknown/unsupported Aristo DB backend".}

# -----------------

proc finish*(db: AristoDbRef; flush = false) =
  ## Backend destructor. The argument `flush` indicates that a full database
  ## deletion is requested. If set ot left `false` the outcome might differ
  ## depending on the type of backend (e.g. the `BackendMemory` backend will
  ## always flush on close.)
  ##
  ## This distructor may be used on already *destructed* descriptors.
  if not db.backend.isNil:
    db.backend.closeFn flush
    db.backend = AristoBackendRef(nil)
  db.top = AristoLayerRef(nil)
  db.stack.setLen(0)

# -----------------

proc to*[W: TypedBackendRef|MemBackendRef](
    db: AristoDbRef;
    T: type W;
      ): T =
  ## Handy helper for lew-level access to some backend functionality
  db.backend.T

# ------------------------------------------------------------------------------
# End
# ------------------------------------------------------------------------------
