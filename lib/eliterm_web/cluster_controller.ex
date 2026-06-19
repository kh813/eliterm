defmodule ElitermWeb.ClusterController do
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  @doc """
  参加ノードからの参加リクエストを処理する API エンドポイント。
  有効なトークンであれば Cookie を暗号化して返却し、トークンを即時破棄する。
  """
  def join_request(conn, %{"token" => token, "node_name" => _node_name, "public_key" => public_key_base64}) do
    public_key = Base.url_decode64!(public_key_base64)
    case Eliterm.Cluster.verify_and_use_token(token, public_key) do
      {:ok, encrypted_cookie} ->
        # 状態変更を PubSub に通知（GUI メニュー等の再描画トリガー）
        if Process.whereis(Eliterm.PubSub) do
          Phoenix.PubSub.broadcast(Eliterm.PubSub, "cluster", :cluster_state_changed)
        end

        json(conn, %{status: "ok", cookie: encrypted_cookie})

      {:error, :no_active_invite} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", reason: "No active invite session on primary node."})

      {:error, :invalid_token} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{status: "error", reason: "Invalid or expired token."})
    end
  end

  def join_request(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{status: "error", reason: "Missing parameters: token, node_name, public_key"})
  end
end
