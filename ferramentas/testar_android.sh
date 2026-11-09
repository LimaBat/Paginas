#!/bin/bash
# Testa o APK no emulador: abre o app, espera o servidor do celular responder e procura erros na tela.
APK=android/app/build/outputs/apk/debug/app-debug.apk
logs() { echo "----- logcat -----"; adb logcat -d | grep -iE "Paginas|chromium|Console|AndroidRuntime|FATAL" | tail -200; }
adb install -r "$APK" || { echo "falha ao instalar"; exit 1; }
adb logcat -c
adb shell am start -n br.paginas.app/.MainActivity
adb forward tcp:47630 tcp:47630
ok=0
for i in $(seq 1 40); do
  if [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:47630/icone.png)" = "200" ]; then ok=1; echo "servidor respondeu após ~$((i*3))s"; break; fi
  sleep 3
done
if [ "$ok" != 1 ]; then echo "O servidor do app não respondeu"; logs; exit 1; fi
sleep 20   # deixa a tela carregar e rodar o JavaScript
if adb logcat -d | grep -E "Uncaught|FATAL EXCEPTION"; then echo "Erro na tela do app"; logs; exit 1; fi
logs | tail -40
echo "TESTE DO ANDROID OK"
