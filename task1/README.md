Задание 1. Ход выполнения работы:

1. Создаем пользователя в системе: sudo adduser testuser;
2. Создаем группу для будущих чтецов: sudo groupadd secretreaders;
3. Добавляем нашего бойца в группу: sudo usermod -aG secretreaders testuser;
4. Далее заходим в рута или через sudo добавляем файл secret.txt и пишем в него secret data;
5. Затем меняем права на файл: chown devops2:secretreaders /opt/secret.txt (владелец файла:группа)
6. Затем прописываем права на файл: 640 /opt/secret.txt (Это означает что владелец может может читать и писать, те кто в группе может читать, а всем остальным сюда нельзя УХАДИТИ)

Проверка работы настройки прав:

Вводим команду:
```bash
ls -la /opt/secret.txt && \
su - testuser -c "cat /opt/secret.txt" && \
su - testuser -c "echo 'hacked' >> /opt/secret.txt"

```

Вывод:

```bash
devops2@Devops2:/opt$ ls -la /opt/secret.txt && su - testuser -c "cat /opt/secret.txt" && su - testuser -c "echo 'hacked' >> /opt/secret.txt"
-rw-r----- 1 devops2 secretreaders 12 Jul  2 07:49 /opt/secret.txt
Password:
secret data
Password:
-bash: line 1: /opt/secret.txt: Permission denied
```


