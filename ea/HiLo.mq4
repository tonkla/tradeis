#property copyright "TRADEiS"
#property link      "https://tradeis.one"
#property version   "1.5"
#property strict

input string secret = "";// Secret spell to summon the EA
input int magic     = 0; // ID of the EA
input double lots   = 0; // Initial lots
input double inc    = 0; // Increased lots from the initial one (Martingale-like)
input int tf        = 0; // Timeframe (60=H1, 1440=D1)
input int period    = 0; // Period
input int max_ords  = 0; // Max orders per side
input int gap       = 0; // Gap between orders (%H-L)
input double xhl    = 0; // Multiplier for median line's slope
input int sl        = 0; // Auto stop loss (%H-L exceeded from H/L)
input int tp        = 0; // Auto take profit (%H-L exceeded from H/L)
input double sl_acc = 0; // Acceptable total loss (%AccountBalance)
input double tp_acc = 0; // Acceptable total profit (%AccountBalance)

int buy_tickets[], sell_tickets[];

double buy_nearest_price, sell_nearest_price;
double pl;
double ma_h0, ma_h1, ma_l0, ma_l1, ma_m0, ma_m1, ma_h_l;
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
    pl += OrderProfit();
  }
}

void get_vars() {
  ma_h0 = iMA(Symbol(), tf, period, 0, MODE_LWMA, PRICE_HIGH, 0);
  ma_h1 = iMA(Symbol(), tf, period, 0, MODE_LWMA, PRICE_HIGH, 1);
  ma_l0 = iMA(Symbol(), tf, period, 0, MODE_LWMA, PRICE_LOW, 0);
  ma_l1 = iMA(Symbol(), tf, period, 0, MODE_LWMA, PRICE_LOW, 1);
  ma_m0 = iMA(Symbol(), tf, period, 0, MODE_LWMA, PRICE_MEDIAN, 0);
  ma_m1 = iMA(Symbol(), tf, period, 0, MODE_LWMA, PRICE_MEDIAN, 1);
  ma_h_l = ma_h0 - ma_l0;
}

void close() {
  if (sl > 0) {
    double _sl = ma_h_l * sl / 100;
    if ((ma_l0 < ma_l1 || Bid < ma_l0 - _sl)
        && ArraySize(buy_tickets) > 0) close_buy_orders();
    if ((ma_h0 > ma_h1 || Ask > ma_h0 + _sl)
        && ArraySize(sell_tickets) > 0) close_sell_orders();
  }

  if (tp > 0) {
    double _tp = ma_h_l * tp / 100;
    if (Bid > ma_h0 + _tp) close_buy_orders();
    if (Ask < ma_l0 - _tp) close_sell_orders();
  }

  if ((sl_acc > 0 && pl < 0 && MathAbs(pl) / AccountBalance() * 100 > sl_acc) ||
      (tp_acc > 0 && pl / AccountBalance() * 100 > tp_acc)) {
    close_buy_orders();
    close_sell_orders();
  }
}

void close_buy_orders() {
  for (int i = 0; i < ArraySize(buy_tickets); i++) {
    if (!OrderSelect(buy_tickets[i], SELECT_BY_TICKET)) continue;
    if (OrderClose(OrderTicket(), OrderLots(), Bid, 3)) buy_closed_time = TimeCurrent();
  }
}

void close_sell_orders() {
  for (int i = 0; i < ArraySize(sell_tickets); i++) {
    if (!OrderSelect(sell_tickets[i], SELECT_BY_TICKET)) continue;
    if (OrderClose(OrderTicket(), OrderLots(), Ask, 3)) sell_closed_time = TimeCurrent();
  }
}

void open() {
  double _xhl = MathAbs(ma_m0 - ma_m1) * xhl;
  double _gap = ma_h_l * gap / 100;
  double _sl  = ma_h_l * sl / 100;

  bool should_buy  = ma_l0 > ma_l1 // Uptrend, higher low
                  && Ask < ma_l0 + _xhl && Bid > ma_l0 - _sl // Lower than the median line slope
                  && buy_closed_time < iTime(Symbol(), PERIOD_H1, 0) // Sleep after closed
                  && (buy_nearest_price == 0 || buy_nearest_price - Ask > _gap) // Order gap, buy lower
                  && ArraySize(buy_tickets) < max_ords; // Not more than max orders

  bool should_sell = ma_h0 < ma_h1 // Downtrend, lower high
                  && Bid > ma_h0 - _xhl && Ask < ma_h0 + _sl // Higher than the median line slope
                  && sell_closed_time < iTime(Symbol(), PERIOD_H1, 0) // Sleep after closed
                  && (sell_nearest_price == 0 || Bid - sell_nearest_price > _gap) // Order gap, sell higher
                  && ArraySize(sell_tickets) < max_ords; // Not more than max orders

  if (should_buy) {
    double _lots = ArraySize(buy_tickets) == 0
                    ? lots
                    : Ask < buy_nearest_price
                      ? NormalizeDouble(ArraySize(buy_tickets) * inc + lots, 2)
                      : lots;
    if (0 < OrderSend(Symbol(), OP_BUY, _lots, Ask, 3, 0, 0, NULL, magic, 0)) return;
  }

  if (should_sell) {
    double _lots = ArraySize(sell_tickets) == 0
                    ? lots
                    : Bid > sell_nearest_price
                      ? NormalizeDouble(ArraySize(sell_tickets) * inc + lots, 2)
                      : lots;
    if (0 < OrderSend(Symbol(), OP_SELL, _lots, Bid, 3, 0, 0, NULL, magic, 0)) return;
  }
}
