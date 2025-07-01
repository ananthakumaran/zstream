defmodule Zstream.EncryptionCoder.AES do
  @moduledoc """
  Implements AES encryption (128, 192, 256) as described in https://www.winzip.com/en/support/aes-encryption

  Supports both AE-1 and AE-2 formats:
  - AE-1: Exposes the CRC-32 in the zip file
  - AE-2: Does not expose the CRC-32 in the zip file (more secure, recommended)

  ## Options

    * `:key_size` - The AES key size in bits. Valid values are 128, 192, or 256. Defaults to 256.
    * `:ae_version` - The AES encryption format version. Valid values are 1 or 2. Defaults to 2.
  """
  @behaviour Zstream.EncryptionCoder

  @aes_block_size 16

  # https://www.winzip.com/en/support/aes-encryption/#key-generation
  @pbkdf2_iterations 1000
  # https://www.winzip.com/en/support/aes-encryption/#salt
  @pbkdf2_salt_lengths %{128 => 8, 192 => 12, 256 => 16}
  # https://www.winzip.com/en/support/aes-encryption/#pwd-verify
  @password_verify_length 2

  # AES key sizes in bytes
  @aes_key_sizes %{128 => 16, 192 => 24, 256 => 32}
  # AES mode indicators for extra field
  @aes_mode_indicators %{128 => 0x01, 192 => 0x02, 256 => 0x03}
  # AES algorithm names for :crypto
  @aes_algorithms %{128 => :aes_128_ecb, 192 => :aes_192_ecb, 256 => :aes_256_ecb}

  defmodule State do
    defstruct mac_state: nil,
              crypto_state: nil,
              encrypted_file_header: <<>>,
              counter: 1,
              buffer: <<>>,
              key_size: 256
  end

  @impl true
  def init(opts) do
    password = Keyword.fetch!(opts, :password)
    key_size = Keyword.get(opts, :key_size, 256)
    ae_version = Keyword.get(opts, :ae_version, 2)

    if key_size not in [128, 192, 256] do
      raise ArgumentError, "Invalid key_size: #{key_size}. Must be 128, 192, or 256."
    end

    if ae_version not in [1, 2] do
      raise ArgumentError, "Invalid ae_version: #{ae_version}. Must be 1 or 2."
    end

    aes_key_length = @aes_key_sizes[key_size]
    salt = :crypto.strong_rand_bytes(@pbkdf2_salt_lengths[key_size])

    <<
      encryption_key::binary-size(aes_key_length),
      hmac_key::binary-size(aes_key_length),
      password_verify::binary-size(@password_verify_length)
    >> =
      :crypto.pbkdf2_hmac(
        :sha,
        password,
        salt,
        @pbkdf2_iterations,
        aes_key_length + aes_key_length + @password_verify_length
      )

    %State{
      encrypted_file_header: salt <> password_verify,
      crypto_state: :crypto.crypto_init(@aes_algorithms[key_size], encryption_key, true),
      mac_state: :crypto.mac_init(:hmac, :sha, hmac_key),
      counter: 1,
      key_size: key_size
    }
  end

  @impl true
  def encode(chunk, state) do
    if state.encrypted_file_header != <<>> do
      {encrypted, updated_state} = encrypt_chunk(chunk, %{state | encrypted_file_header: <<>>})
      {[state.encrypted_file_header, encrypted], updated_state}
    else
      encrypt_chunk(chunk, state)
    end
  end

  defp encrypt_chunk(
         chunk,
         %State{buffer: buffer, counter: counter, crypto_state: crypto_state} = state
       ) do
    input = IO.iodata_to_binary([buffer, chunk])
    input_size = byte_size(input)

    if input_size < @aes_block_size do
      {<<>>, %{state | buffer: input}}
    else
      block_count = div(input_size, @aes_block_size)
      blocks = Enum.map(counter..(counter + block_count - 1), &<<&1::unsigned-little-128>>)
      plaintext_size = block_count * @aes_block_size
      <<plaintext::binary-size(plaintext_size), new_buffer::binary>> = input
      cipher = :crypto.exor(plaintext, :crypto.crypto_update(crypto_state, blocks))

      {
        cipher,
        %{
          state
          | mac_state: :crypto.mac_update(state.mac_state, cipher),
            counter: counter + block_count,
            buffer: new_buffer
        }
      }
    end
  end

  @impl true
  def close(%State{buffer: buffer, counter: counter, crypto_state: crypto_state} = state) do
    buffer_size = byte_size(buffer)

    {final_encrypted, final_state} =
      if buffer_size > 0 do
        last_block = <<counter::unsigned-little-128>>

        cipher =
          :crypto.exor(
            buffer,
            binary_part(:crypto.crypto_update(crypto_state, last_block), 0, buffer_size)
          )

        final_state = %{
          state
          | mac_state: :crypto.mac_update(state.mac_state, cipher),
            counter: counter + 1,
            buffer: <<>>
        }

        {cipher, final_state}
      else
        {<<>>, state}
      end

    # https://www.winzip.com/win/en/aes_info.html#auth-faq
    auth_code = binary_part(:crypto.mac_final(final_state.mac_state), 0, 10)
    _should_be_empty = :crypto.crypto_final(final_state.crypto_state)

    final_encrypted <> auth_code
  end

  # https://www.winzip.com/en/support/aes-encryption/#comp-method
  @impl true
  def general_purpose_flag do
    # which means encrypted (0x0001)
    0x0001
  end

  # https://www.winzip.com/en/support/aes-encryption/#comp-method
  # a compression method of 99 is used to indicate the presence of an AES-encrypted file
  @impl true
  def compression_method, do: 99

  # https://www.winzip.com/en/support/aes-encryption/#extra-data
  @impl true
  def extra_field_data(options) do
    {coder, _options} = Keyword.fetch!(options, :coder)
    {_encryption_coder, encryption_options} = Keyword.fetch!(options, :encryption_coder)
    key_size = Keyword.get(encryption_options, :key_size, 256)
    ae_version = Keyword.get(encryption_options, :ae_version, 2)

    <<
      # Extra field header ID
      0x9901::little-size(16),
      # Data size
      7::little-size(16),
      # Integer version number specific to the zip vendor, 0x0001 ae-1, 0x0002 ae-2
      ae_version::little-size(16),
      # 2-character vendor ID
      "AE"::binary,
      # Integer mode value indicating AES encryption strength
      @aes_mode_indicators[key_size]::little-size(8),
      # Actual compression method used (8=deflate, 0=stored)
      coder.compression_method()::little-size(16)
    >>
  end

  @impl true
  def version_needed_to_extract, do: 51

  @impl true
  def crc_exposed?(options) do
    {_encryption_coder, encryption_options} = Keyword.fetch!(options, :encryption_coder)
    ae_version = Keyword.get(encryption_options, :ae_version, 2)
    ae_version == 1
  end
end
