class_name CryptoStateReplicator
extends RefCounted

const KEY_BYTES: int = 32
const IV_BYTES: int = 16

## Encrypts the authoritative GameState and produces 2-of-3 threshold key shares for the 3 non-host seats.
static func create_replicated_checkpoint(state: GameState, host_seat: int) -> Dictionary:
	var json_str: String = JSON.stringify(state.to_authoritative_dict())
	var raw_bytes: PackedByteArray = json_str.to_utf8_buffer()

	# PKCS#7 padding to 16-byte block boundary for AES-256-CBC
	var pad_len: int = 16 - (raw_bytes.size() % 16)
	for i in range(pad_len):
		raw_bytes.append(pad_len)

	var crypto := Crypto.new()
	var master_key: PackedByteArray = crypto.generate_random_bytes(KEY_BYTES)
	var iv: PackedByteArray = crypto.generate_random_bytes(IV_BYTES)

	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT, master_key, iv)
	var ciphertext: PackedByteArray = aes.update(raw_bytes)
	aes.finish()

	# Compute SHA-256 digest of plaintext for post-recovery verification
	var sha256_hex: String = _sha256_buffer(raw_bytes)

	# 2-of-3 Combinatorial XOR Secret Sharing: master_key = s1 XOR s2 XOR s3
	var s1: PackedByteArray = crypto.generate_random_bytes(KEY_BYTES)
	var s2: PackedByteArray = crypto.generate_random_bytes(KEY_BYTES)
	var s3: PackedByteArray = _xor_bytes(_xor_bytes(master_key, s1), s2)

	var client_seats: Array[int] = []
	for seat in range(4):
		if seat != host_seat:
			client_seats.append(seat)

	# Distribute pairs: Client[0] gets (s1, s2), Client[1] gets (s2, s3), Client[2] gets (s3, s1)
	var seat_shares: Dictionary = {
		client_seats[0]: {"s1": Marshalls.raw_to_base64(s1), "s2": Marshalls.raw_to_base64(s2)},
		client_seats[1]: {"s2": Marshalls.raw_to_base64(s2), "s3": Marshalls.raw_to_base64(s3)},
		client_seats[2]: {"s3": Marshalls.raw_to_base64(s3), "s1": Marshalls.raw_to_base64(s1)}
	}

	return {
		"envelope": {
			"state_revision": state.state_revision,
			"iv_b64": Marshalls.raw_to_base64(iv),
			"ciphertext_b64": Marshalls.raw_to_base64(ciphertext),
			"plaintext_sha256": sha256_hex
		},
		"seat_shares": seat_shares
	}

## Reconstructs the AES-256 master key from any 2 surviving clients' share dictionaries and decrypts the state.
static func recover_state_from_shares(envelope: Dictionary, collected_shares: Array[Dictionary]) -> GameState:
	var merged: Dictionary = {}
	for share_bundle in collected_shares:
		for k in share_bundle.keys():
			merged[k] = share_bundle[k]

	if not (merged.has("s1") and merged.has("s2") and merged.has("s3")):
		push_error("CryptoStateReplicator: Insufficient key shares to reconstruct master key.")
		return null

	var s1: PackedByteArray = Marshalls.base64_to_raw(str(merged["s1"]))
	var s2: PackedByteArray = Marshalls.base64_to_raw(str(merged["s2"]))
	var s3: PackedByteArray = Marshalls.base64_to_raw(str(merged["s3"]))
	var master_key: PackedByteArray = _xor_bytes(_xor_bytes(s1, s2), s3)

	var iv: PackedByteArray = Marshalls.base64_to_raw(str(envelope["iv_b64"]))
	var ciphertext: PackedByteArray = Marshalls.base64_to_raw(str(envelope["ciphertext_b64"]))

	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_DECRYPT, master_key, iv)
	var padded_plain: PackedByteArray = aes.update(ciphertext)
	aes.finish()

	var computed_sha: String = _sha256_buffer(padded_plain)
	if computed_sha != str(envelope["plaintext_sha256"]):
		push_error("CryptoStateReplicator: Checksum mismatch during host migration decryption!")
		return null

	# Remove PKCS#7 padding
	var pad_len: int = padded_plain[padded_plain.size() - 1]
	if pad_len < 1 or pad_len > 16 or pad_len > padded_plain.size():
		return null
	var unpadded: PackedByteArray = padded_plain.slice(0, padded_plain.size() - pad_len)

	var json_str: String = unpadded.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(json_str)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null

	return GameState.from_authoritative_dict(parsed)

static func _xor_bytes(a: PackedByteArray, b: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(a.size())
	for i in range(a.size()):
		out[i] = a[i] ^ b[i]
	return out

static func _sha256_buffer(buf: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(buf)
	return ctx.finish().hex_encode()
    