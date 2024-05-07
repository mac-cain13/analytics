defmodule Plausible.Stats.QueryTest do
  use Plausible.DataCase, async: true
  alias Plausible.Stats.Query

  setup do
    user = insert(:user)

    site =
      insert(:site,
        members: [user],
        inserted_at: ~N[2020-01-01T00:00:00],
        stats_start_date: ~D[2020-01-01]
      )

    {:ok, site: site, user: user}
  end

  @tag :slow
  test "keeps current timestamp so that utc_boundaries don't depend on time passing by", %{
    site: site
  } do
    q1 = %{now: %NaiveDateTime{}} = Query.from(site, %{"period" => "realtime"})
    q2 = %{now: %NaiveDateTime{}} = Query.from(site, %{"period" => "30m"})
    boundaries1 = Plausible.Stats.Base.utc_boundaries(q1, site)
    boundaries2 = Plausible.Stats.Base.utc_boundaries(q2, site)
    :timer.sleep(1500)
    assert ^boundaries1 = Plausible.Stats.Base.utc_boundaries(q1, site)
    assert ^boundaries2 = Plausible.Stats.Base.utc_boundaries(q2, site)
  end

  test "parses day format", %{site: site} do
    q = Query.from(site, %{"period" => "day", "date" => "2019-01-01"})

    assert q.date_range.first == ~D[2019-01-01]
    assert q.date_range.last == ~D[2019-01-01]
    assert q.interval == "hour"
  end

  test "day format defaults to today", %{site: site} do
    q = Query.from(site, %{"period" => "day"})

    assert q.date_range.first == Timex.today()
    assert q.date_range.last == Timex.today()
    assert q.interval == "hour"
  end

  test "parses realtime format", %{site: site} do
    q = Query.from(site, %{"period" => "realtime"})

    assert q.date_range.first == Timex.today()
    assert q.date_range.last == Timex.today()
    assert q.period == "realtime"
  end

  test "parses month format", %{site: site} do
    q = Query.from(site, %{"period" => "month", "date" => "2019-01-01"})

    assert q.date_range.first == ~D[2019-01-01]
    assert q.date_range.last == ~D[2019-01-31]
    assert q.interval == "date"
  end

  test "parses 6 month format", %{site: site} do
    q = Query.from(site, %{"period" => "6mo"})

    assert q.date_range.first ==
             Timex.shift(Timex.today(), months: -5) |> Timex.beginning_of_month()

    assert q.date_range.last == Timex.today() |> Timex.end_of_month()
    assert q.interval == "month"
  end

  test "parses 12 month format", %{site: site} do
    q = Query.from(site, %{"period" => "12mo"})

    assert q.date_range.first ==
             Timex.shift(Timex.today(), months: -11) |> Timex.beginning_of_month()

    assert q.date_range.last == Timex.today() |> Timex.end_of_month()
    assert q.interval == "month"
  end

  test "parses year to date format", %{site: site} do
    q = Query.from(site, %{"period" => "year"})

    assert q.date_range.first ==
             Timex.now(site.timezone) |> Timex.to_date() |> Timex.beginning_of_year()

    assert q.date_range.last ==
             Timex.now(site.timezone) |> Timex.to_date() |> Timex.end_of_year()

    assert q.interval == "month"
  end

  test "parses all time", %{site: site} do
    q = Query.from(site, %{"period" => "all"})

    assert q.date_range.first == NaiveDateTime.to_date(site.inserted_at)
    assert q.date_range.last == Timex.today()
    assert q.period == "all"
    assert q.interval == "month"
  end

  test "parses all time in correct timezone", %{site: site} do
    site = Map.put(site, :timezone, "America/Cancun")
    q = Query.from(site, %{"period" => "all"})

    assert q.date_range.first == ~D[2019-12-31]
    assert q.date_range.last == Timex.today("America/Cancun")
  end

  test "all time shows today if site has no start date", %{site: site} do
    site = Map.put(site, :stats_start_date, nil)
    q = Query.from(site, %{"period" => "all"})

    assert q.date_range.first == Timex.today()
    assert q.date_range.last == Timex.today()
    assert q.period == "all"
    assert q.interval == "hour"
  end

  test "all time shows hourly if site is completely new", %{site: site} do
    site = Map.put(site, :stats_start_date, Timex.now() |> Timex.to_date())
    q = Query.from(site, %{"period" => "all"})

    assert q.date_range.first == Timex.today()
    assert q.date_range.last == Timex.today()
    assert q.period == "all"
    assert q.interval == "hour"
  end

  test "all time shows daily if site is more than a day old", %{site: site} do
    site =
      Map.put(site, :stats_start_date, Timex.now() |> Timex.shift(days: -1) |> Timex.to_date())

    q = Query.from(site, %{"period" => "all"})

    assert q.date_range.first == Timex.today() |> Timex.shift(days: -1)
    assert q.date_range.last == Timex.today()
    assert q.period == "all"
    assert q.interval == "date"
  end

  test "all time shows monthly if site is more than a month old", %{site: site} do
    site =
      Map.put(site, :stats_start_date, Timex.now() |> Timex.shift(months: -1) |> Timex.to_date())

    q = Query.from(site, %{"period" => "all"})

    assert q.date_range.first == Timex.today() |> Timex.shift(months: -1)
    assert q.date_range.last == Timex.today()
    assert q.period == "all"
    assert q.interval == "month"
  end

  test "all time uses passed interval different from the default interval", %{site: site} do
    site =
      Map.put(site, :stats_start_date, Timex.now() |> Timex.shift(months: -1) |> Timex.to_date())

    q = Query.from(site, %{"period" => "all", "interval" => "week"})

    assert q.date_range.first == Timex.today() |> Timex.shift(months: -1)
    assert q.date_range.last == Timex.today()
    assert q.period == "all"
    assert q.interval == "week"
  end

  test "defaults to 30 days format", %{site: site} do
    assert Query.from(site, %{}) == Query.from(site, %{"period" => "30d"})
  end

  test "parses custom format", %{site: site} do
    q = Query.from(site, %{"period" => "custom", "from" => "2019-01-01", "to" => "2019-01-15"})

    assert q.date_range.first == ~D[2019-01-01]
    assert q.date_range.last == ~D[2019-01-15]
    assert q.interval == "date"
  end

  @tag :ee_only
  test "adds sample_threshold :infinite to query struct", %{site: site} do
    q = Query.from(site, %{"period" => "30d", "sample_threshold" => "infinite"})
    assert q.sample_threshold == :infinite
  end

  @tag :ee_only
  test "casts sample_threshold to integer in query struct", %{site: site} do
    q = Query.from(site, %{"period" => "30d", "sample_threshold" => "30000000"})
    assert q.sample_threshold == 30_000_000
  end

  describe "filters" do
    test "parses goal filter", %{site: site} do
      filters = Jason.encode!(%{"goal" => "Signup"})
      q = Query.from(site, %{"period" => "6mo", "filters" => filters})

      assert q.filters["event:goal"] == {:is, {:event, "Signup"}}
    end

    test "parses source filter", %{site: site} do
      filters = Jason.encode!(%{"source" => "Twitter"})
      q = Query.from(site, %{"period" => "6mo", "filters" => filters})

      assert q.filters["visit:source"] == {:is, "Twitter"}
    end
  end

  describe "include_imported" do
    setup [:create_site]

    test "is true when requested via params and imported data exists", %{site: site} do
      insert(:site_import, site: site)
      site = Plausible.Imported.load_import_data(site)

      assert %{include_imported: true} =
               Query.from(site, %{"period" => "day", "with_imported" => "true"})
    end

    test "is false when imported data does not exist", %{site: site} do
      assert %{include_imported: false} =
               Query.from(site, %{"period" => "day", "with_imported" => "true"})
    end

    test "is false when imported data exists but is out of the date range", %{site: site} do
      insert(:site_import, site: site, start_date: ~D[2021-01-01], end_date: ~D[2022-01-01])
      site = Plausible.Imported.load_import_data(site)

      assert %{include_imported: false} =
               Query.from(site, %{"period" => "day", "with_imported" => "true"})
    end

    test "is false in realtime even when imported data from today exists", %{site: site} do
      insert(:site_import, site: site)
      site = Plausible.Imported.load_import_data(site)

      assert %{include_imported: false} =
               Query.from(site, %{"period" => "realtime", "with_imported" => "true"})
    end

    test "is false when an arbitrary custom property filter is used", %{site: site} do
      insert(:site_import, site: site)
      site = Plausible.Imported.load_import_data(site)

      assert %{include_imported: false} =
               Query.from(site, %{
                 "period" => "day",
                 "with_imported" => "true",
                 "property" => "event:props:url",
                 "filters" => Jason.encode!(%{"props" => %{"author" => "!John Doe"}})
               })
    end

    test "is true when breaking down by url and filtering by outbound link or file download goal",
         %{site: site} do
      insert(:site_import, site: site)
      site = Plausible.Imported.load_import_data(site)

      Enum.each(["Outbound Link: Click", "File Download"], fn goal_name ->
        assert %{include_imported: true} =
                 Query.from(site, %{
                   "period" => "day",
                   "with_imported" => "true",
                   "property" => "event:props:url",
                   "filters" => Jason.encode!(%{"goal" => goal_name})
                 })
      end)
    end

    test "is false when breaking down by url but without a special goal filter",
         %{site: site} do
      insert(:site_import, site: site)
      site = Plausible.Imported.load_import_data(site)

      assert %{include_imported: false} =
               Query.from(site, %{
                 "period" => "day",
                 "with_imported" => "true",
                 "property" => "event:props:url"
               })
    end
  end
end
