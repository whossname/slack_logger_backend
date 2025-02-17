ExUnit.start()

defmodule SlackLoggerBackendTest do
  use ExUnit.Case
  require Logger

  setup do
    bypass = Bypass.open()
    url = "http://localhost:#{bypass.port}/hook"
    Application.put_env(:slack_logger_backend, :slack_webhook, url)
    Application.put_env(:slack_logger_backend, :levels, [:warn, :error])

    on_exit(fn ->
      Logger.remove_backend(SlackLoggerBackend.Logger, flush: true)
      SlackLoggerBackend.stop(nil)
    end)

    {:ok, %{bypass: bypass, url: url}}
  end

  defp start() do
    {:ok, _} = Logger.add_backend(SlackLoggerBackend.Logger, flush: true)
    SlackLoggerBackend.start(nil, nil)
  end

  test "posts the error to the Slack incoming webhook", %{bypass: bypass} do
    start()

    Bypass.expect(bypass, fn conn ->
      assert "/hook" == conn.request_path
      assert "POST" == conn.method
      Plug.Conn.resp(conn, 200, "ok")
    end)

    Logger.error("This error should be logged to Slack")
    Logger.flush()
    :timer.sleep(100)
  end

  test "doesn't post a debug message to Slack if the level is not set", %{bypass: _bypass} do
    start()
    Logger.debug("This message should not be logged to Slack")
    Logger.flush()
    :timer.sleep(100)
  end

  test "environment variable overrides config", %{bypass: bypass, url: url} do
    System.put_env("SLACK_LOGGER_WEBHOOK_URL", url <> "_use_environment_variable")
    start()

    Bypass.expect(bypass, fn conn ->
      assert "/hook_use_environment_variable" == conn.request_path
      assert "POST" == conn.method
      Plug.Conn.resp(conn, 200, "ok")
    end)

    Logger.error("This error should be logged to Slack")
    Logger.flush()
    :timer.sleep(100)
    System.delete_env("SLACK_LOGGER_WEBHOOK_URL")
  end

  test "debounce prevents deplicate messages from being sent", %{bypass: bypass} do
    Application.put_env(:slack_logger_backend, :debounce_seconds, 1)
    start()

    Bypass.expect_once(bypass, fn conn ->
      assert "/hook" == conn.request_path
      assert "POST" == conn.method
      Plug.Conn.resp(conn, 200, "ok")
    end)

    for _ <- 0..1, do: Logger.error("This error should be logged to Slack only once")

    :timer.sleep(1100)
    Logger.flush()

    Application.delete_env(:slack_logger_backend, :debounce_seconds)
  end

  test "ignores error messages in the ignore list", %{bypass: bypass} do
    msg1 = "I don't want to see this"
    msg2 = "I    also don't want to see this"
    msg3 = "But I do want to see this"

    Application.put_env(:slack_logger_backend, :ignore, [msg1, msg2])
    start()

    Bypass.expect_once(bypass, fn conn ->
      assert "/hook" == conn.request_path
      assert "POST" == conn.method
      Plug.Conn.resp(conn, 200, "ok")
    end)

    Logger.error(msg1)
    Logger.error(String.replace(msg2, ~r/\s+/, " "))

    Logger.error("""
    I don't want
    to see this
    """)

    Logger.error(msg3)

    Logger.flush()
    :timer.sleep(100)
  end

  defmodule IgnoredModule do
    def send_error(error) do
      Logger.error(error)
    end
  end

  test "ignores error events in the ignore list, key-value list", %{bypass: bypass} do
    ignore = [
      [module: IgnoredModule],
      [function: "send_error/1"]
    ]

    Application.put_env(:slack_logger_backend, :ignore, ignore)
    start()

    Bypass.expect_once(bypass, fn conn ->
      assert "/hook" == conn.request_path
      assert "POST" == conn.method
      Plug.Conn.resp(conn, 200, "ok")
    end)

    msg1 = "I don't want to see this"
    msg2 = "But I do want to see this"

    IgnoredModule.send_error(msg1)

    Logger.error(msg2)

    Logger.flush()
    :timer.sleep(100)
  end
end
