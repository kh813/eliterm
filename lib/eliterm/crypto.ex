defmodule Eliterm.Crypto do
  @moduledoc """
  一時的な公開鍵・秘密鍵ペアの生成、およびそれを用いたCookieの暗号化・復号を担当するセキュリティモジュール。
  外部の依存関係を追加せず、Erlang 標準の :public_key モジュール（RSA 2048-bit）を利用する。
  """

  @doc """
  一時的な RSA 2048-bit 鍵ペアを生成する。
  返り値は `{private_key_tuple, public_key_der}`。
  `public_key_der` はバイナリ形式の公開鍵データで、HTTP リクエストで転送しやすい形式。
  """
  def generate_keypair do
    private_key = :public_key.generate_key({:rsa, 2048, 65537})
    # Extract modulus and publicExponent to build {:RSAPublicKey, modulus, public_exponent}
    modulus = elem(private_key, 2)
    public_exponent = elem(private_key, 3)
    public_key = {:RSAPublicKey, modulus, public_exponent}
    public_key_der = :public_key.der_encode(:RSAPublicKey, public_key)
    {private_key, public_key_der}
  end

  @doc """
  参加ノードから送られてきた公開鍵（DER符号化バイナリ）を用いて、クラスタの Cookie を暗号化する。
  暗号化したクッキーは、転送用に Base64 エンコードした文字列で返す。
  """
  def encrypt_cookie(cookie, public_key_der) when is_binary(cookie) and is_binary(public_key_der) do
    decoded_pub = :public_key.der_decode(:RSAPublicKey, public_key_der)
    encrypted = :public_key.encrypt_public(cookie, decoded_pub, rsa_pad: :rsa_pkcs1_padding)
    Base.url_encode64(encrypted)
  end

  @doc """
  自身の秘密鍵（タプル構造）を用いて、暗号化されて送られてきた Base64 クッキー文字列を復号する。
  """
  def decrypt_cookie(encrypted_base64, private_key) when is_binary(encrypted_base64) do
    encrypted = Base.url_decode64!(encrypted_base64)
    :public_key.decrypt_private(encrypted, private_key, rsa_pad: :rsa_pkcs1_padding)
  end
end
