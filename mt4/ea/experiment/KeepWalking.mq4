#property copyright "TRADEiS"
#property link      "https://tradeis.one"
#property version   "1.1"
#property strict

input string secret = "";// Secret spell to summon the EA
input int magic     = 0; // ID of the EA
input double lots   = 0; // Initial lots
input double inc    = 0; // Increased lots from the initial one (Martingale-like)
input int start_gmt = 0; // Starting hour in GMT
input int stop_gmt  = 0; // Stopping hour in GMT
input int orders    = 0; // Maximum orders per side
input int gap       = 0; // Gap between orders in %ATR
input int sleep     = 0; // Seconds to sleep since loss
input int tp        = 0; // Take profit in %ATR
input bool sl       = 0; // Stop the old opposite one

int buy_tickets[], sell_tickets[], buy_count, sell_count;
double buy_nearest_price, sell_nearest_price, buy_pl, sell_pl, atr;
datetime buy_closed_time, sell_closed_time;
bool start;


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
  buy_pl = 0;
  sell_pl = 0;

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
        buy_pl += Bid - OrderOpenPrice();
        break;
      case OP_SELL:
        size = ArraySize(sell_tickets);
        ArrayResize(sell_tickets, size + 1);
        sell_tickets[size] = OrderTicket();
        if (sell_nearest_price == 0 || MathAbs(OrderOpenPrice() - Bid) < MathAbs(sell_nearest_price - Bid)) {
          sell_nearest_price = OrderOpenPrice();
        }
        sell_pl += OrderOpenPrice() - Ask;
        break;
    }
  }

  buy_count = ArraySize(buy_tickets);
  sell_count = ArraySize(sell_tickets);
}

void get_vars() {
  atr = iATR(Symbol(), PERIOD_D1, 3, 0);
}

void close() {
  if (stop_gmt >= 0 && TimeHour(TimeGMT()) >= stop_gmt) {
    if (buy_count > 0) close_buy_orders();
    if (sell_count > 0) close_sell_orders();
    start = false;
    return;
  }

  if (sl && buy_count > 0 && sell_count > 0) {
    double _sl = 0.05 * atr;
    if (buy_pl < 0 && sell_pl > _sl) close_buy_orders();
    if (sell_pl < 0 && buy_pl > _sl) close_sell_orders();
  }

  if (tp > 0 && buy_pl + sell_pl > tp * atr / 100) {
    if (buy_count > 0) close_buy_orders();
    if (sell_count > 0) close_sell_orders();
    start = false;
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
  if (!start) {
    if (TimeHour(TimeGMT()) == start_gmt) start = true;
    else return;
  }

  double _open = iOpen(Symbol(), PERIOD_D1, 0);
  double _gap = gap * atr / 100;
  double min = 0.05 * atr;
  double max = 0.20 * atr;

  bool should_buy  = Ask > _open + min
                  && TimeCurrent() - buy_closed_time > sleep
                  && (buy_count == 0 ? Ask < _open + max : Ask > buy_nearest_price + _gap)
                  && buy_count < orders;

  bool should_sell = Bid < _open - min
                  && TimeCurrent() - sell_closed_time > sleep
                  && (sell_count == 0 ? Bid > _open - max : Bid < sell_nearest_price - _gap)
                  && sell_count < orders;

  if (should_buy) {
    double _lots = buy_count == 0 ? lots : NormalizeDouble(buy_count * inc + lots, 2);
    if (0 < OrderSend(Symbol(), OP_BUY, _lots, Ask, 3, 0, 0, NULL, magic, 0)) return;
  }

  if (should_sell) {
    double _lots = sell_count == 0 ? lots : NormalizeDouble(sell_count * inc + lots, 2);
    if (0 < OrderSend(Symbol(), OP_SELL, _lots, Bid, 3, 0, 0, NULL, magic, 0)) return;
  }
}
