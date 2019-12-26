#property copyright "TRADEiS"
#property link      "https://tradeis.one"
#property version   "1.0"
#property strict

input string secret = "";// Secret spell to summon the EA
input int magic     = 0; // ID of the EA
input float lots    = 0; // Lots
input int period    = 0; // Number of bars consumed by indicators
input bool force_sl = 0; // Force stop loss when trend changed
input int sl        = 0; // Auto stop loss (%H-L)
input int tp        = 0; // Auto take profit (%H-L)
input double xhl    = 0; // Percent threshold (%H-L)

int buy_ticket, sell_ticket;
double o, c;
double ma_h0, ma_l0, hlx;
datetime closed_time;


int OnInit() {
  return secret == "https://tradeis.one" ? INIT_SUCCEEDED : INIT_FAILED;
}

void OnTick() {
  get_order();
  get_vars();
  close();
  open();
}

void get_order() {
  buy_ticket = 0;
  sell_ticket = 0;

  for (int i = OrdersTotal() - 1; i >= 0; i--) {
    if (!OrderSelect(i, SELECT_BY_POS)) continue;
    if (OrderSymbol() != Symbol() || OrderMagicNumber() != magic) continue;
    switch (OrderType()) {
      case OP_BUY:
        buy_ticket = OrderTicket();
        break;
      case OP_SELL:
        sell_ticket = OrderTicket();
        break;
    }
  }
}

void get_vars() {
  o = iOpen(Symbol(), PERIOD_H1, 0);
  c = iClose(Symbol(), PERIOD_H1, 0);
  ma_h0 = iMA(Symbol(), PERIOD_H1, period, 0, MODE_SMA, PRICE_HIGH, 0);
  ma_l0 = iMA(Symbol(), PERIOD_H1, period, 0, MODE_SMA, PRICE_LOW, 0);
  hlx = (ma_h0 - ma_l0) * xhl / 100;
}

void close() {
  double buy_pips = 0;
  double sell_pips = 0;

  if (buy_ticket > 0 && OrderSelect(buy_ticket, SELECT_BY_TICKET))
    buy_pips = Bid - OrderOpenPrice();
  if (sell_ticket > 0 && OrderSelect(sell_ticket, SELECT_BY_TICKET))
    sell_pips = OrderOpenPrice() - Ask;

  if (sl > 0 && (buy_pips < 0 || sell_pips < 0)) {
    double _sl = (ma_h0 - ma_l0) * sl / 100;
    if (buy_pips < 0 && MathAbs(buy_pips) > _sl) close_buy_order();
    if (sell_pips < 0 && MathAbs(sell_pips) > _sl) close_sell_order();
  }

  if (tp > 0 && (buy_pips > 0 || sell_pips > 0)) {
    double _tp = (ma_h0 - ma_l0) * tp / 100;
    if (buy_pips > _tp) close_buy_order();
    if (sell_pips > _tp) close_sell_order();
  }

  if (force_sl) {
    if (o - c > hlx) close_buy_order();
    if (c - o > hlx) close_sell_order();
  }
}

void close_buy_order() {
  if (!OrderSelect(buy_ticket, SELECT_BY_TICKET)) return;
  if (OrderClose(OrderTicket(), OrderLots(), Bid, 3))
    closed_time = iTime(Symbol(), PERIOD_H1, 0);
}

void close_sell_order() {
  if (!OrderSelect(sell_ticket, SELECT_BY_TICKET)) return;
  if (OrderClose(OrderTicket(), OrderLots(), Ask, 3))
    closed_time = iTime(Symbol(), PERIOD_H1, 0);
}

void open() {
  if (buy_ticket > 0 || sell_ticket > 0) return;
  if (closed_time > 0 && closed_time == iTime(Symbol(), PERIOD_H1, 0)) return;

  if (c - o > hlx)
    int i = OrderSend(Symbol(), OP_BUY, lots, Ask, 3, 0, 0, NULL, magic, 0);

  if (o - c > hlx)
    int i = OrderSend(Symbol(), OP_SELL, lots, Bid, 3, 0, 0, NULL, magic, 0);
}
