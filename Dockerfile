FROM nimlang/nim:1.6.6-alpine-onbuild
RUN nimble webclient
ENTRYPOINT ["./kino_server"]
EXPOSE 9001/tcp
