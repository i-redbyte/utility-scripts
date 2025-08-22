#!/usr/bin/env bash
set -euo pipefail
echo "************************************"
echo "* [Red_byte] macbook battery state *"
echo "************************************"

wlen() { printf "%s" "$1" | wc -m | tr -d ' '; }
rep()  { local ch="$1" n="$2"; ((n>0)) && printf "%*s" "$n" "" | sed "s/ /$ch/g"; }
pad()  { local n="${1:-0}"; ((n>0)) && printf "%*s" "$n" "" || true; }
row()  { local L="$1" V="$2"; local padl=$((LW-$(wlen "$L"))); local padr=$((VW-$(wlen "$V")));
         printf "│ %s" "$L"; pad "$padl"; printf " │ "; pad "$padr"; printf "%s │\n" "$V"; }
yn()   { case "${1:-}" in 1|yes|Yes|true|True) echo "Да";; 0|no|No|false|False) echo "Нет";; *) echo "—";; esac; }
mins() { local m="$1"; [[ "$m" =~ ^[0-9]+$ && $m -lt 14400 ]] || { echo "—"; return; } # < 10 суток
         local h=$((m/60)); local r=$((m%60)); ((h>0)) && printf "%d ч %d мин" "$h" "$r" || printf "%d мин" "$m"; }

cc=""; max=""; design=""; cur=""; ext=""; charging=""; full=""
ttr_min=""; ttf_min=""; volt_mV=""; amp_mA=""; temp_dK=""; manu=""; dev=""; serial=""

xml="$(ioreg -r -c AppleSmartBattery -a 2>/dev/null || true)"
if [[ -n "$xml" ]]; then
  while IFS=$'\t' read -r k v; do
    case "$k" in
      cc|max|design|cur|ttr_min|ttf_min|volt_mV|amp_mA|temp_dK) printf -v "$k" "%s" "$v" ;;
      ext|charging|full) [[ "$v" == "true/" ]] && printf -v "$k" "1" || { [[ "$v" == "false/" ]] && printf -v "$k" "0"; } ;;
      manu|dev|serial) printf -v "$k" "%s" "$v" ;;
    esac
  done < <(
    printf "%s" "$xml" | plutil -extract 0 xml1 -o - - 2>/dev/null | \
    awk -F'[<>]' '
      function emit(k,v){ printf "%s\t%s\n", k, v }
      $2=="key"&&$3=="CycleCount"         {getline; emit("cc",$3)}
      $2=="key"&&$3=="MaxCapacity"        {getline; emit("max",$3)}
      $2=="key"&&$3=="DesignCapacity"     {getline; emit("design",$3)}
      $2=="key"&&$3=="CurrentCapacity"    {getline; emit("cur",$3)}
      $2=="key"&&$3=="TimeRemaining"      {getline; emit("ttr_min",$3)}
      $2=="key"&&$3=="TimeToFullCharge"   {getline; emit("ttf_min",$3)}
      $2=="key"&&$3=="Voltage"            {getline; emit("volt_mV",$3)}
      $2=="key"&&$3=="Amperage"           {getline; emit("amp_mA",$3)}
      $2=="key"&&$3=="Temperature"        {getline; emit("temp_dK",$3)}
      $2=="key"&&$3=="IsCharging"         {getline; emit("charging",$2)}
      $2=="key"&&$3=="ExternalConnected"  {getline; emit("ext",$2)}
      $2=="key"&&$3=="FullyCharged"       {getline; emit("full",$2)}
      $2=="key"&&$3=="Manufacturer"       {getline; emit("manu",$3)}
      $2=="key"&&$3=="DeviceName"         {getline; emit("dev",$3)}
      $2=="key"&&$3=="BatterySerialNumber"{getline; emit("serial",$3)}
      $2=="key"&&$3=="Serial"             {getline; emit("serial",$3)}
    '
  )
fi

t="$(ioreg -w0 -rc AppleSmartBattery 2>/dev/null || true)"
if [[ -n "$t" ]]; then
  [[ -z "$cc"     ]] && cc=$(   sed -nE 's/.*"CycleCount" = ([0-9]+).*/\1/p'            <<<"$t" | head -n1)
  [[ -z "$max"    ]] && max=$(  sed -nE 's/.*"MaxCapacity" = ([0-9]+).*/\1/p'           <<<"$t" | head -n1)
  [[ -z "$design" ]] && design=$(sed -nE 's/.*"DesignCapacity" = ([0-9]+).*/\1/p'       <<<"$t" | head -n1)
  [[ -z "$cur"    ]] && cur=$(  sed -nE 's/.*"CurrentCapacity" = ([0-9]+).*/\1/p'       <<<"$t" | head -n1)
  [[ -z "$volt_mV" ]] && volt_mV=$(sed -nE 's/.*"Voltage" = ([0-9]+).*/\1/p'            <<<"$t" | head -n1)
  [[ -z "$amp_mA" ]] && amp_mA=$( sed -nE 's/.*"Amperage" = (-?[0-9]+).*/\1/p'          <<<"$t" | head -n1)
  [[ -z "$temp_dK" ]] && temp_dK=$(sed -nE 's/.*"Temperature" = ([0-9]+).*/\1/p'        <<<"$t" | head -n1)
  [[ -z "$charging" ]] && { v=$(sed -nE 's/.*"IsCharging" = (Yes|No).*/\1/p'            <<<"$t" | head -n1); [[ "$v" == "Yes" ]] && charging=1 || [[ "$v" == "No" ]] && charging=0 || true; }
  [[ -z "$ext"      ]] && { v=$(sed -nE 's/.*"ExternalConnected" = (Yes|No).*/\1/p'     <<<"$t" | head -n1); [[ "$v" == "Yes" ]] && ext=1      || [[ "$v" == "No" ]] && ext=0      || true; }
  [[ -z "$full"     ]] && { v=$(sed -nE 's/.*"FullyCharged" = (Yes|No).*/\1/p'          <<<"$t" | head -n1); [[ "$v" == "Yes" ]] && full=1     || [[ "$v" == "No" ]] && full=0     || true; }
fi

b="$(pmset -g batt 2>/dev/null || true)"

is_int(){ [[ "${1:-}" =~ ^-?[0-9]+$ ]]; }
clip_num(){ local x="$1" lo="$2" hi="$3"; is_int "$x" || { echo ""; return; }; ((x<lo||x>hi)) && echo "" || echo "$x"; }

volt_mV="$(clip_num "${volt_mV:-}" 3000 20000)"
amp_mA="$(clip_num "${amp_mA:-}" -100000 100000)"
temp_dK="$(clip_num "${temp_dK:-}" 0 10000)"
ttr_min="$(clip_num "${ttr_min:-}" 0 20000)"
ttf_min="$(clip_num "${ttf_min:-}" 0 20000)"

soc="—"; if is_int "${cur:-}" && is_int "${max:-}" && ((max>0)); then soc=$(awk -v a="$cur" -v b="$max" 'BEGIN{printf "%.1f%%",(a/b)*100}'); fi
health="—"; if is_int "${max:-}" && is_int "${design:-}" && ((design>0)); then health=$(awk -v a="$max" -v b="$design" 'BEGIN{printf "%.1f%%",(a/b)*100}'); fi
volt_str="—"; [[ -n "${volt_mV:-}" ]] && volt_str=$(awk -v mv="$volt_mV" 'BEGIN{printf "%.2f V", mv/1000}')
amp_str="—";  [[ -n "${amp_mA:-}"  ]] && amp_str=$(printf "%d mA%s" "$amp_mA" $([ "$amp_mA" -lt 0 ] && echo " (разряд)" || { [ "$amp_mA" -gt 0 ] && echo " (заряд)"; }))
temp_str="—"; [[ -n "${temp_dK:-}" ]] && temp_str=$(awk -v t="$temp_dK" 'BEGIN{printf "%.1f °C",(t/10.0-273.15)}')

# ---------- таблица ----------
UNIT="mAh"
H1="Показатель"; H2="Значение"
L1="Количество циклов";          V1="${cc:-—}"
L2="Текущий заряд";              V2=$([[ -n "${cur:-}" && -n "${soc:-}" && "$soc" != "—" ]] && printf "%s %s (%s)" "$cur" "$UNIT" "$soc" || { [[ -n "${cur:-}" ]] && printf "%s %s" "$cur" "$UNIT" || echo "—"; })
L3="Максимальная ёмкость";       V3=$([[ -n "${max:-}"    ]] && printf "%s %s" "$max" "$UNIT"    || echo "—")
L4="Проектная ёмкость";          V4=$([[ -n "${design:-}" ]] && printf "%s %s" "$design" "$UNIT" || echo "—")
L5="Здоровье батареи";           V5="$health"
L6="Подключено к питанию";       V6="$(yn "${ext:-}")"
L7="Идёт зарядка";               V7="$(yn "${charging:-}")"
L8="Полностью заряжена";         V8="$(yn "${full:-}")"
L9="Оставшееся время (разряд)";  V9="$(mins "${ttr_min:-}")"
L10="До полного заряда";         V10="$(mins "${ttf_min:-}")"
L11="Напряжение";                V11="$volt_str"
L12="Ток";                       V12="$amp_str"
L13="Температура";               V13="$temp_str"
L14="Производитель";             V14="${manu:-—}"
L15="Модель (имя)";              V15="${dev:-—}"
L16="Серийный номер";            V16="${serial:-—}"

LW=$(wlen "$H1"); for s in "$L1" "$L2" "$L3" "$L4" "$L5" "$L6" "$L7" "$L8" "$L9" "$L10" "$L11" "$L12" "$L13" "$L14" "$L15" "$L16"; do t=$(wlen "$s"); ((t>LW)) && LW=$t; done
VW=$(wlen "$H2"); for s in "$V1" "$V2" "$V3" "$V4" "$V5" "$V6" "$V7" "$V8" "$V9" "$V10" "$V11" "$V12" "$V13" "$V14" "$V15" "$V16"; do t=$(wlen "$s"); ((t>VW)) && VW=$t; done

TOP="┌$(rep '─' $((LW+2)))┬$(rep '─' $((VW+2)))┐"
MID="├$(rep '─' $((LW+2)))┼$(rep '─' $((VW+2)))┤"
BOT="└$(rep '─' $((LW+2)))┴$(rep '─' $((VW+2)))┘"

printf "%s\n" "$TOP"
row "$H1" "$H2"; printf "%s\n" "$MID"
row "$L1" "$V1"; row "$L2" "$V2"; row "$L3" "$V3"; row "$L4" "$V4"; row "$L5" "$V5"
row "$L6" "$V6"; row "$L7" "$V7"; row "$L8" "$V8"; row "$L9" "$V9"; row "$L10" "$V10"
row "$L11" "$V11"; row "$L12" "$V12"; row "$L13" "$V13"; row "$L14" "$V14"; row "$L15" "$V15"; row "$L16" "$V16"
printf "%s\n" "$BOT"
