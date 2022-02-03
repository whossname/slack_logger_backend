ExUnit.start()

defmodule SlackLoggerBackendTest do
  use ExUnit.Case
  require Logger

  setup do
    bypass = Bypass.open()
    url = "http://localhost:#{bypass.port}/hook"
    Application.put_env(SlackLoggerBackend, :slack, url: url)
    Application.put_env(SlackLoggerBackend, :levels, [:debug, :info, :warn, :error])
    SlackLoggerBackend.start(nil, nil)

    on_exit(fn ->
      Logger.remove_backend(SlackLoggerBackend.Logger, flush: true)
      SlackLoggerBackend.stop(nil)
    end)

    {:ok, %{bypass: bypass, url: url}}
  end

  test "posts the error to the Slack incoming webhook", %{bypass: bypass} do
    Application.put_env(SlackLoggerBackend, :levels, [:error])

    on_exit(fn ->
      Application.put_env(SlackLoggerBackend, :levels, [:debug, :info, :warn, :error])
    end)

    Bypass.expect(bypass, fn conn ->
      assert "/hook" == conn.request_path
      assert "POST" == conn.method
      Plug.Conn.resp(conn, 200, "ok")
    end)

    Logger.error("This error should be logged to Slack")
    Logger.flush()
    :timer.sleep(100)
  end

  test "doesn't post a debug message to Slack if the level is not set", %{bypass: bypass} do
    Application.put_env(SlackLoggerBackend, :levels, [:info])

    on_exit(fn ->
      Application.put_env(SlackLoggerBackend, :levels, [:debug, :info, :warn, :error])
    end)

    Bypass.expect(bypass, fn _conn ->
      flunk("Slack should not have been notified")
    end)

    Bypass.pass(bypass)

    Logger.error("This error should not be logged to Slack")
    Logger.flush()
    :timer.sleep(100)
  end

  test "environment variable overrides config", %{bypass: bypass, url: url} do
    Application.put_env(SlackLoggerBackend, :levels, [:error])
    System.put_env("SLACK_LOGGER_WEBHOOK_URL", url <> "_use_environment_variable")

    on_exit(fn ->
      Application.put_env(SlackLoggerBackend, :levels, [:debug, :info, :warn, :error])
    end)

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
    Application.put_env(SlackLoggerBackend, :levels, [:error])
    Application.put_env(:slack_logger_backend, :debounce_seconds, 1)

    on_exit(fn ->
      Application.put_env(SlackLoggerBackend, :levels, [:debug, :info, :warn, :error])
    end)

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
end
