#property copyright "TRADEiS"
#property link      "https://tradeis.one"
#property version   "1.0"
#property strict

input string secret     = "";// Secret spell to summon the EA
input int magic_f       = 0; // ID of trend following strategy
input double lots       = 0; // Lots
input int tf            = 0; // Timeframe
input int period        = 0; // Period
input int max_orders_f  = 0; // Maximum allowed orders
input int max_spread    = 0; // Maximum allowed spread
input double gap        = 0; // Gap between orders in %ATR
input double slx_f      = 0; // Stop loss by total in %ATR
input double tpx_f      = 0; // Take profit by total in %ATR
input int start_gmt     = -1;// Starting hour in GMT
input int stop_gmt      = -1;// Stopping hour in GMT
input int friday_gmt    = -1;// Close all on Friday hour in GMT

bool start=false;
datetime buy_closed_time_f, sell_closed_time_f;

int OnInit() {
  return secret == "https://tradeis.one" ? INIT_SUCCEEDED : INIT_FAILED;
}

void OnTick() {
  // Prevent abnormal spread
  if (MarketInfo(Symbol(), MODE_SPREAD) > max_spread) return;

  int buy_tickets_f[], sell_tickets_f[], buy_count_f=0, sell_count_f=0;
  double buy_nearest_price_f=0, sell_nearest_price_f=0;
  double buy_pl_f=0, sell_pl_f=0;

  int size;
  for (int i = OrdersTotal() - 1; i >= 0; i--) {
    if (!OrderSelect(i, SELECT_BY_POS)) continue;
    if (OrderSymbol() != Symbol() || OrderMagicNumber() == 0) continue;
    if (OrderMagicNumber() == magic_f) {
      switch (OrderType()) {
        case OP_BUY:
          size = ArraySize(buy_tickets_f);
          ArrayResize(buy_tickets_f, size + 1);
          buy_tickets_f[size] = OrderTicket();
          if (buy_nearest_price_f == 0 || MathAbs(OrderOpenPrice() - Ask) < MathAbs(buy_nearest_price_f - Ask)) {
            buy_nearest_price_f = OrderOpenPrice();
          }
          buy_pl_f += Bid - OrderOpenPrice();
          break;
        case OP_SELL:
          size = ArraySize(sell_tickets_f);
          ArrayResize(sell_tickets_f, size + 1);
          sell_tickets_f[size] = OrderTicket();
          if (sell_nearest_price_f == 0 || MathAbs(OrderOpenPrice() - Bid) < MathAbs(sell_nearest_price_f - Bid)) {
            sell_nearest_price_f = OrderOpenPrice();
          }
          sell_pl_f += OrderOpenPrice() - Ask;
          break;
      }
    }
  }

  buy_count_f = ArraySize(buy_tickets_f);
  sell_count_f = ArraySize(sell_tickets_f);

  double ma_h0, ma_l0, ma_m0, ma_m1, ma_hl;

  ma_h0 = iMA(Symbol(), tf, period, 0, MODE_LWMA, PRICE_HIGH, 0);
  ma_l0 = iMA(Symbol(), tf, period, 0, MODE_LWMA, PRICE_LOW, 0);
  ma_m0 = iMA(Symbol(), tf, period, 0, MODE_LWMA, PRICE_MEDIAN, 0);
  ma_m1 = iMA(Symbol(), tf, period, 0, MODE_LWMA, PRICE_MEDIAN, 1);
  ma_hl = ma_h0 - ma_l0;

  // Close --------------------------------------------------------------------

  if (stop_gmt >= 0 && TimeHour(TimeGMT()) >= stop_gmt) {
    close_buy_orders(buy_tickets_f);
    close_sell_orders(sell_tickets_f);
    start = false;
    return;
  }
  if (friday_gmt > 0 && TimeHour(TimeGMT()) >= friday_gmt && DayOfWeek() == 5) {
    close_buy_orders(buy_tickets_f);
    close_sell_orders(sell_tickets_f);
    return;
  }

  // Stop Loss ------------------------

  if (buy_pl_f < 0 && MathAbs(buy_pl_f) > slx_f * ma_hl) {
    for (int i = 0; i < buy_count_f; i++) {
      if (!OrderSelect(buy_tickets_f[i], SELECT_BY_TICKET)) continue;
      if (OrderClose(OrderTicket(), OrderLots(), Bid, 3)) buy_closed_time_f = TimeCurrent();
    }
  }
  if (sell_pl_f < 0 && MathAbs(sell_pl_f) > slx_f * ma_hl) {
    for (int i = 0; i < sell_count_f; i++) {
      if (!OrderSelect(sell_tickets_f[i], SELECT_BY_TICKET)) continue;
      if (OrderClose(OrderTicket(), OrderLots(), Ask, 3)) sell_closed_time_f = TimeCurrent();
    }
  }

  // Take Profit ----------------------

  if (buy_pl_f > tpx_f * ma_hl) {
    for (int i = 0; i < buy_count_f; i++) {
      if (!OrderSelect(buy_tickets_f[i], SELECT_BY_TICKET)) continue;
      if (OrderClose(OrderTicket(), OrderLots(), Bid, 3)) buy_closed_time_f = TimeCurrent();
    }
  }
  if (sell_pl_f > tpx_f * ma_hl) {
    for (int i = 0; i < sell_count_f; i++) {
      if (!OrderSelect(sell_tickets_f[i], SELECT_BY_TICKET)) continue;
      if (OrderClose(OrderTicket(), OrderLots(), Ask, 3)) sell_closed_time_f = TimeCurrent();
    }
  }

  // Open ---------------------------------------------------------------------

  if (start_gmt >= 0 && !start) {
    if (TimeHour(TimeGMT()) < start_gmt || TimeHour(TimeGMT()) >= stop_gmt) return;
    start = true;
  }
  if (friday_gmt > 0 && TimeHour(TimeGMT()) >= friday_gmt && DayOfWeek() == 5) return;

  bool should_buy=false, should_sell=false;

  // Follow ---------------------------

  if (magic_f > 0) {
    double h0 = iHigh(Symbol(), tf, 0);
    double h1 = iHigh(Symbol(), tf, 1);
    double h2 = iHigh(Symbol(), tf, 2);
    double l0 = iLow(Symbol(), tf, 0);
    double l1 = iLow(Symbol(), tf, 1);
    double l2 = iLow(Symbol(), tf, 2);

    should_buy   = ma_m1 < ma_m0
                && buy_count_f < max_orders_f
                && TimeCurrent() - buy_closed_time_f > 300
                && (buy_count_f == 0
                    ? Ask < ma_m0 || (Ask < ma_h0 && l2 < l1 && l1 < l0)
                    : MathAbs(Ask - buy_nearest_price_f) > gap * ma_hl);

    if (should_buy && OrderSend(Symbol(), OP_BUY, lots, Ask, 3, 0, 0, "f", magic_f, 0) > 0) return;

    should_sell  = ma_m1 > ma_m0
                && sell_count_f < max_orders_f
                && TimeCurrent() - sell_closed_time_f > 300
                && (sell_count_f == 0
                    ? Bid > ma_m0 || (Bid > ma_l0 && h2 > h1 && h1 > h0)
                    : MathAbs(Bid - sell_nearest_price_f > gap * ma_hl);

    if (should_sell && OrderSend(Symbol(), OP_SELL, lots, Bid, 3, 0, 0, "f", magic_f, 0) > 0) return;
  }
}

void close_buy_orders(int &buy_tickets[]) {
  for (int i = 0; i < ArraySize(buy_tickets); i++) {
    if (!OrderSelect(buy_tickets[i], SELECT_BY_TICKET)) continue;
    if (OrderClose(OrderTicket(), OrderLots(), Bid, 3)) continue;
  }
}

void close_sell_orders(int &sell_tickets[]) {
  for (int i = 0; i < ArraySize(sell_tickets); i++) {
    if (!OrderSelect(sell_tickets[i], SELECT_BY_TICKET)) continue;
    if (OrderClose(OrderTicket(), OrderLots(), Ask, 3)) continue;
  }
}
