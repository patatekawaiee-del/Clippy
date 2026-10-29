#pragma once
#include <string>
#include <memory>
#include <cstdint>

class Recorder {
public:
    static Recorder& get();
    bool start(std::string const& path, int w, int h);
    void addFrame(uint8_t const* rgba, double time); // RGBA, bas->haut (GL)
    void finish();
    bool isRecording() const;
    void share(std::string const& path);
private:
    Recorder();
    ~Recorder();
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};
