#property copyright "TRADEiS"
#property link      "https://tradeis.one"
#property version   "1.6"
#property strict

input string secret = "";// Secret spell to summon the EA
input int magic     = 0; // ID of the EA
input double lots   = 0; // Initial lots
input double inc    = 0; // Increased lots from the initial one (Martingale-like)
input int tf        = 0; // Timeframe
input int orders    = 0; // Limited orders per side
input int gap_bwd   = 0; // Backward gap between orders (%H-L)
input int gap_fwd   = 0; // Forward gap between orders (%H-L)
input int sleep     = 0; // Seconds to sleep since loss
input int time_sl   = 0; // Seconds to stop since open
input int sl        = 0; // Auto stop loss (%H-L)
input int tp        = 0; // Auto take profit (%H-L)
input double acc_sl = 0; // Acceptable total loss (%AccountBalance)
input double acc_tp = 0; // Acceptable total profit (%AccountBalance)
input bool trend_sl = 0; // Force SL when trend changed
input bool hl_sl    = 0; // Force SL when the order exceeds H/L
input bool friday   = 0; // Close all on late Friday

int buy_tickets[], sell_tickets[], buy_count, sell_count;
int calc_round;
double buy_nearest_price, sell_nearest_price, pl;
double h0, h1, l0, l1, m0, m1;
double ma_h0, ma_l0, ma_h_l, slope;
datetime buy_closed_time, sell_closed_time;


int OnInit() {
  return secret == "https://tradeis.one" ? INIT_SUCCEEDED : INIT_FAILED;
}

void OnTick() {
  get_orders();
  get_vars();
  close();
  open();
}

void get_orders() {
  int size = 0;
  ArrayFree(buy_tickets);
  ArrayFree(sell_tickets);
  buy_nearest_price = 0;
  sell_nearest_price = 0;
  pl = 0;

  for (int i = OrdersTotal() - 1; i >= 0; i--) {
    if (!OrderSelect(i, SELECT_BY_POS)) continue;
    if (OrderSymbol() != Symbol() || OrderMagicNumber() != magic) continue;
    switch (OrderType()) {
      case OP_BUY:
        size = ArraySize(buy_tickets);
        ArrayResize(buy_tickets, size + 1);
        buy_tickets[size] = OrderTicket();
        if (buy_nearest_price == 0 || MathAbs(OrderOpenPrice() - Ask) < MathAbs(buy_nearest_price - Ask)) {
          buy_nearest_price = OrderOpenPrice();
        }
        break;
      case OP_SELL:
        size = ArraySize(sell_tickets);
        ArrayResize(sell_tickets, size + 1);
        sell_tickets[size] = OrderTicket();
        if (sell_nearest_price == 0 || MathAbs(OrderOpenPrice() - Bid) < MathAbs(sell_nearest_price - Bid)) {
          sell_nearest_price = OrderOpenPrice();
        }
        break;
    }
    pl += OrderProfit() + OrderCommission() + OrderSwap();
  }

  buy_count = ArraySize(buy_tickets);
  sell_count = ArraySize(sell_tickets);
}

void get_vars() {
  h0 = iHigh(Symbol(), 1, iHighest(Symbol(), 1, MODE_HIGH, tf, 0));
  l0 = iLow(Symbol(), 1, iLowest(Symbol(), 1, MODE_LOW, tf, 0));
  h1 = iHigh(Symbol(), 1, iHighest(Symbol(), 1, MODE_HIGH, tf, tf));
  l1 = iLow(Symbol(), 1, iLowest(Symbol(), 1, MODE_LOW, tf, tf));

  m0 = ((h0 - l0) / 2) + l0;
  m1 = ((h1 - l1) / 2) + l1;
  ma_h0 = (h0 + h1) / 2;
  ma_l0 = (l0 + l1) / 2;
  ma_h_l = ma_h0 - ma_l0;
  slope = MathAbs(m0 - m1) / ma_h_l * 100;

  if (calc_round < 20) calc_round++;
}

void close() {
  if (friday && TimeHour(TimeGMT()) >= 21 && DayOfWeek() == 5) {
    if (buy_count > 0) close_buy_orders();
    if (sell_count > 0) close_sell_orders();
    return;
  }

  if ((acc_sl > 0 && pl < 0 && MathAbs(pl) / AccountBalance() * 100 > acc_sl) ||
      (acc_tp > 0 && pl / AccountBalance() * 100 > acc_tp)) {
    if (buy_count > 0) close_buy_orders();
    if (sell_count > 0) close_sell_orders();
  }

  if (trend_sl) {
    if (m0 < m1 && buy_count > 0) close_buy_orders();
    if (m0 > m1 && sell_count > 0) close_sell_orders();
  }

  if (hl_sl) {
    for (int i = 0; i < buy_count; i++) {
      if (!OrderSelect(buy_tickets[i], SELECT_BY_TICKET)) continue;
      if (OrderOpenPrice() > ma_h0
          && OrderClose(OrderTicket(), OrderLots(), Bid, 3))
        buy_closed_time = TimeCurrent();
    }
    for (int i = 0; i < sell_count; i++) {
      if (!OrderSelect(sell_tickets[i], SELECT_BY_TICKET)) continue;
      if (OrderOpenPrice() < ma_l0
          && OrderClose(OrderTicket(), OrderLots(), Ask, 3))
        sell_closed_time = TimeCurrent();
    }
  }

  if (time_sl > 0) {
    for (int i = 0; i < buy_count; i++) {
      if (!OrderSelect(buy_tickets[i], SELECT_BY_TICKET)) continue;
      if (TimeCurrent() - OrderOpenTime() > time_sl
          && OrderClose(OrderTicket(), OrderLots(), Bid, 3)) continue;
    }
    for (int i = 0; i < sell_count; i++) {
      if (!OrderSelect(sell_tickets[i], SELECT_BY_TICKET)) continue;
      if (TimeCurrent() - OrderOpenTime() > time_sl
          && OrderClose(OrderTicket(), OrderLots(), Ask, 3)) continue;
    }
  }

  if (sl > 0) {
    double _sl = sl * ma_h_l / 100;
    for (int i = 0; i < buy_count; i++) {
      if (!OrderSelect(buy_tickets[i], SELECT_BY_TICKET)) continue;
      if (OrderProfit() < 0 && OrderOpenPrice() - Bid > _sl
          && OrderClose(OrderTicket(), OrderLots(), Bid, 3))
        buy_closed_time = TimeCurrent();
    }
    for (int i = 0; i < sell_count; i++) {
      if (!OrderSelect(sell_tickets[i], SELECT_BY_TICKET)) continue;
      if (OrderProfit() < 0 && Ask - OrderOpenPrice() > _sl
          && OrderClose(OrderTicket(), OrderLots(), Ask, 3))
        sell_closed_time = TimeCurrent();
    }
  }

  if (tp > 0) {
    double _tp = tp * ma_h_l / 100;
    for (int i = 0; i < buy_count; i++) {
      if (!OrderSelect(buy_tickets[i], SELECT_BY_TICKET)) continue;
      if (Bid - OrderOpenPrice() > _tp
          && OrderClose(OrderTicket(), OrderLots(), Bid, 3)) continue;
    }
    for (int i = 0; i < sell_count; i++) {
      if (!OrderSelect(sell_tickets[i], SELECT_BY_TICKET)) continue;
      if (OrderOpenPrice() - Ask > _tp
          && OrderClose(OrderTicket(), OrderLots(), Ask, 3)) continue;
    }
  }
}

void close_buy_orders() {
  for (int i = 0; i < buy_count; i++) {
    if (!OrderSelect(buy_tickets[i], SELECT_BY_TICKET)) continue;
    if (OrderClose(OrderTicket(), OrderLots(), Bid, 3)) buy_closed_time = TimeCurrent();
  }
}

void close_sell_orders() {
  for (int i = 0; i < sell_count; i++) {
    if (!OrderSelect(sell_tickets[i], SELECT_BY_TICKET)) continue;
    if (OrderClose(OrderTicket(), OrderLots(), Ask, 3)) sell_closed_time = TimeCurrent();
  }
}

void open() {
  if (calc_round < 20) return; // It needs time to fetch previous bars of M1
  if (slope < 20) return; // Sideway
  if (friday && TimeHour(TimeGMT()) >= 21 && DayOfWeek() == 5) return; // Rest on Friday, 21:00 GMT

  int hidx = iHighest(Symbol(), 1, MODE_HIGH, 5, 0);
  int lidx = iLowest(Symbol(), 1, MODE_LOW, 5, 0);
  double h = iHigh(Symbol(), 1, hidx);
  double l = iLow(Symbol(), 1, lidx);
  double t = 0.4 * (h - l);

  bool should_buy  = m0 > m1 // Uptrend, higher high-low
                  && (hidx == 0 && h - Ask < Bid - l && Bid - l > t) // Moving up
                  && Ask < ma_h0 - (0.2 * ma_h_l) // Highest buy zone
                  && TimeCurrent() - buy_closed_time > sleep // Take a break after loss
                  && buy_count < orders // Limited buy orders
                  && (buy_count == 0 ||
                      ((gap_bwd > 0 && buy_nearest_price - Ask > gap_bwd * ma_h_l / 100) ||
                       (gap_fwd > 0 && Ask - buy_nearest_price > gap_fwd * ma_h_l / 100))); // Orders gap

  bool should_sell = m0 < m1 // Downtrend, lower high-low
                  && (lidx == 0 && h - Ask > Bid - l && h - Ask > t) // Moving down
                  && Bid > ma_l0 + (0.2 * ma_h_l) // Lowest sell zone
                  && TimeCurrent() - sell_closed_time > sleep // Take a break after loss
                  && sell_count < orders // Limited sell orders
                  && (sell_count == 0 ||
                      ((gap_bwd > 0 && Bid - sell_nearest_price > gap_bwd * ma_h_l / 100) ||
                       (gap_fwd > 0 && sell_nearest_price - Bid > gap_fwd * ma_h_l / 100))); // Orders gap

  if (should_buy) {
    double _lots = inc == 0 ? lots
                    : buy_count == 0 ? lots
                      : Ask > buy_nearest_price ? lots
                        : NormalizeDouble(buy_count * inc + lots, 2);
    if (0 < OrderSend(Symbol(), OP_BUY, _lots, Ask, 3, 0, 0, NULL, magic, 0)) return;
  }

  if (should_sell) {
    double _lots = inc == 0 ? lots
                    : sell_count == 0 ? lots
                      : Bid < sell_nearest_price ? lots
                        : NormalizeDouble(sell_count * inc + lots, 2);
    if (0 < OrderSend(Symbol(), OP_SELL, _lots, Bid, 3, 0, 0, NULL, magic, 0)) return;
  }
}
